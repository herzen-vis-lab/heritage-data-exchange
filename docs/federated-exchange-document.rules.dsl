# Heritage Data Exchange — правила протокола v0.0.8 (черновик)
#
# Правила задают поведение узлов федеративной сети: валидацию документов,
# провенанс атрибутов, жизненный цикл дедупликации, семантику конвертов,
# согласование классификаторов (НСИ). Правила исполняются каждым узлом
# локально (governance через артефакты, а не через центральный орган).

# ─────────────────────────────────────────────────────────────────────────
# 1. Валидация документа
# ─────────────────────────────────────────────────────────────────────────

rule document.required_fields {
  description: "Документ обмена обязан содержать идентификатор, стандарт, версию и метку времени"
  require: federated_exchange_document_guid, standard, version, generated_at
  on_violation: reject_document
}

rule document.uuid_format {
  description: "Все глобальные идентификаторы — UUID v4, нижний регистр, неизменяемы после присвоения"
  pattern: uuid_v4_lowercase
  scope: federation_node_guid, digital_object_guid, person_guid, relation_guid, source_node_guid, asserted_by_node_guid
  on_violation: reject_document
}

rule document.version {
  description: "Версия документа обязана совпадать с версией протокола узла-отправителя"
  match: version == protocol_version(sender_node_guid)
  on_violation: reject_document
}

# ─────────────────────────────────────────────────────────────────────────
# 2. Узлы сети
# ─────────────────────────────────────────────────────────────────────────

rule node.registration {
  description: "Узел обязан пройти регистрацию до первого обмена; federation_node_guid уникален в федерации"
  require: federation_node_guid in federation_registry
  uniqueness: federation_node_guid
  on_violation: reject_envelope
}

rule node.endpoint {
  description: "federation_node_url обязан быть доступным HTTPS-адресом сервиса узла"
  constraint: scheme(federation_node_url) == "https"
  on_violation: warn
}

# ─────────────────────────────────────────────────────────────────────────
# 3. Объекты
# ─────────────────────────────────────────────────────────────────────────

rule object.guid_immutable {
  description: "digital_object_guid присваивается организацией-источником и не изменяется при обогащении"
  constraint: digital_object_guid unchanged_across_envelopes
  on_violation: reject_envelope
}

rule object.local_identifier {
  description: "Локальный идентификатор (например, АК1) обязателен при publish и уникален в пределах узла-источника"
  require: local_identifier for each published object
  uniqueness: (federation_node_guid, local_identifier)
  on_violation: reject_envelope
}

rule object.media {
  description: "Каждая карточка обязана ссылаться на цифровую репрезентацию (media) и каноническую запись (record)"
  require: digital_object_media_url, record_url
  on_violation: warn
}

# ─────────────────────────────────────────────────────────────────────────
# 4. Провенанс атрибутов и классификаций
# ─────────────────────────────────────────────────────────────────────────

rule metadata.provenance {
  description: "Каждый атрибут обязан указывать узел-источник; атрибут без провенанса не участвует в обогащении"
  require: source_node_guid for each metadata item
  on_violation: drop_attribute
}

rule metadata.expert_attribution {
  description: "Атрибуция выполняется экспертом узла: атрибуты, требующие экспертной верификации, обязаны указывать asserted_by_person_guid; уровень верификации фиксируется attribution_status"
  require: asserted_by_person_guid if attribution_required(key)
  statuses: attribution_status in [unverified, expert_verified, authoritative]
  on_violation: drop_attribute
}

rule person.registration {
  description: "Эксперт обязан быть зарегистрирован в узле и пройти верификацию уровня знаний до участия в атрибуции"
  require: person_guid in node.experts
  on_violation: reject_attribution
}

rule person.scoping {
  description: "Идентичность персоны узловая: person_guid уникален в пределах узла; полная идентичность — пара (federation_node_guid, person_guid). Глобального реестра персон нет"
  uniqueness: (federation_node_guid, person_guid)
  scope: asserted_by_person_guid разрешается в связке с source_node_guid атрибута
  on_violation: reject_attribution
}

rule metadata.conflict {
  description: "При противоречии атрибутов разных узлов оба значения сохраняются с пометкой source_node_guid; приоритет — у авторитетного источника (authority) или эксперта"
  precedence: authority_uri > expert(attribution_status) > source_node_guid
  on_conflict: keep_both_with_provenance
}

rule classification.authority {
  description: "Классификация обязана ссылаться на авторитетный словарь; коды без authority не распространяются"
  require: authority for each classification item
  allowed_authorities: aat, ulan, lcsh, viaf, federation_classifier_registry
  on_violation: reject_envelope
}

# ─────────────────────────────────────────────────────────────────────────
# 5. Жизненный цикл дедупликации
# ─────────────────────────────────────────────────────────────────────────
# Дедупликация — локальная операция узла: при получении конверта узел
# проверяет карточки на дубликаты в своей БД. Результат распространяется
# теми же конвертами publish в виде связей Relation.

rule dedup.local_check {
  description: "Узел проверяет полученные карточки на дубликаты локально, в своей БД"
  trigger: publish received
  action: compare(classification.group, attributes) in local_database
}

rule dedup.candidate {
  description: "Обнаруженный дубликат публикуется связью со статусом candidate_match"
  action: publish Relation(status = candidate_match, asserted_by_node_guid = self)
}

rule dedup.confirm {
  description: "candidate_match переводится в confirmed_match при согласии обеих сторон (обе карточки участвуют) или по решению авторитетного узла; результат публикуется конвертом publish"
  condition: confirmed_by(source_node) AND confirmed_by(target_node)
  alt_condition: authority_decision(relation.authority)
  action: publish Relation(status = confirmed_match)
}

rule dedup.reject {
  description: "Любая из сторон может отклонить связь; rejected_match публикуется с указанием инициатора и не пересматривается без новых данных"
  trigger: disagreement(reason != null)
  action: publish Relation(status = rejected_match)
}

rule dedup.enrichment {
  description: "После confirmed_match атрибуты обеих карточек взаимно обогащаются; каждая сторона сохраняет провенанс своих атрибутов"
  action: merge_attributes(card_a, card_b) with provenance
  result: publish broadcast с полным снимком (атрибуты обеих сторон)
}

rule merge.provenance {
  description: "Получатель выполняет merge по провенансу: атрибуты с разными source_node_guid не затирают друг друга; снимок отправителя не гарантирует глобальную полноту (асинхронность)"
  action: keep_by_source_node_guid
  on_violation: warn
}

rule merge.master_record {
  description: "Мастер-запись не выделяется: у каждого узла собственная карточка объекта; карточки связываются (same_as) и взаимно обогащаются по провенансу"
  action: linked_cards_with_provenance
}

rule dedup.return_contribution {
  description: "Подтверждённый вклад возвращается узлу-вкладчику таргетированным конвертом: receiver_node_guid = вкладчик, карточка содержит только атрибуты source_node_guid == receiver_node_guid и связи с его участием"
  action: publish targeted(receiver = contributor)
}

rule event.dedup {
  description: "Дедупликация — отдельное событие матчинга: обнаруженный дубликат фиксируется связью (candidate/confirmed/rejected). Событие матчинга не означает принятия атрибутов другой стороны"
  action: publish Relation(status) — matching only
}

rule event.acceptance {
  description: "Принятие или отклонение конкретного атрибута — отдельное логируемое событие: узел явно соглашается (accepts) или отклоняет (rejects) значение атрибута с обоснованием. В протоколе видно, кто и когда согласился с каким значением, а не только что карточки «взаимно обогатились»"
  require: asserted_by_node_guid, timestamp, target attribute claim
  on_violation: reject_event
}

# ─────────────────────────────────────────────────────────────────────────
# 6. Конверты обмена
# ─────────────────────────────────────────────────────────────────────────

rule envelope.sender {
  description: "sender_node_guid конверта обязан совпадать с federation_node_guid узла-отправителя"
  match: sender_node_guid == self.federation_node_guid
  on_violation: reject_envelope
}

rule envelope.broadcast {
  description: "receiver_node_guid отсутствует — broadcast: полный снимок (все атрибуты со всеми source_node_guid, известные отправителю) подписчикам группы классификатора"
  condition: receiver_node_guid == null implies publish_to_group(classification.group) with full_snapshot
  on_violation: warn
}

rule envelope.direct {
  description: "receiver_node_guid заполнен — таргетированная доставка (возврат вклада): только атрибуты с source_node_guid == receiver_node_guid, связи с участием получателя и минимальный контекст объекта"
  constraint: receiver_node_guid != null implies attributes ⊆ {source_node_guid == receiver_node_guid}
  on_violation: reject_envelope
}

rule envelope.transport {
  description: "Транспортный слой и механизм подписки на группы — предмет реализации и отдельной публикации; целостность и подлинность конверта — задача транспортного слоя (подпись, TLS)"
  out_of_scope: transport, subscription, envelope_signature
}

# ─────────────────────────────────────────────────────────────────────────
# 7. Согласование классификаторов (НСИ)
# ─────────────────────────────────────────────────────────────────────────

rule nsi.versioning {
  description: "Изменение универсального классификатора оформляется новой версией; устаревшие коды получают преемников (successor)"
  action: bump_classifier_version + map deprecated_codes to successors
}

rule nsi.sync {
  description: "Узел публикует карточку с кодом классификатора только после синхронизации актуальной версии словаря"
  require: classifier_snapshot(version) == current
  on_violation: defer_publish
}

rule nsi.dispute {
  description: "Спор о классификации объекта между узлами разрешается по авторитетности словаря или экспертной атрибуцией, фиксируется в карточке"
  precedence: authority_uri > expert(attribution_status)
  action: annotate_dispute_in_classification
}

# ─────────────────────────────────────────────────────────────────────────
# 8. Лицензии и использование данных в ИИ
# ─────────────────────────────────────────────────────────────────────────

rule license.required {
  description: "Объекты, публикуемые в федерации, должны нести как минимум одну лицензию (license) с authority"
  require: license for each published object
  on_violation: warn
}

rule license.authority {
  description: "authority лицензии может ссылаться на любой авторитетный источник (SPDX, Creative Commons, реестры организаций); некоммерческая организация (НКО) — один из возможных вариантов авторитетного источника"
  allowed: any_registered_authority incl. ngo_registry
  on_violation: warn
}

rule authority.flexible {
  description: "Координация сети — через открытые артефакты (формат, классификатор, правила); authority может указывать на любой авторитетный источник, включая НКО, но ни один источник не является управляющим органом сети"
  principle: artifacts_not_organs
}

rule ai.usage {
  description: "Использование значений атрибутов в обучающих данных моделей ИИ разрешено только при is_enabled_for_ai_using = true; отсутствие флага означает запрет (консервативный дефолт)"
  condition: is_enabled_for_ai_using == true implies usable_for_ai_training
  default: false
  on_violation: reject_ai_usage
}

rule ai.attribution {
  description: "При использовании атрибутов в обучающих данных сохраняется атрибуция: source_node_guid и asserted_by_person_guid не удаляются"
  require: provenance preserved in derived datasets
  on_violation: reject_ai_usage
}

rule license.enforcement {
  description: "Исполнение лицензионных условий — вне протокола, в рамках законодательства об исключительных правах (судебная защита); протокол обеспечивает доказуемость через провенанс: license + source_node_guid в карточке и сохранение провенанса в производных данных"
  principle: protocol_provides_evidence, enforcement_is_legal
}

# ─────────────────────────────────────────────────────────────────────────
# 9. Сущности наследия (Work / Manifestation / Item)
# ─────────────────────────────────────────────────────────────────────────

rule entity.identity_registrar {
  description: "Первый регистратор является владельцем записи и идентификатора сущности (Work). Приоритет по времени применяется только к вопросу идентичности и владения записью и не распространяется на истинность атрибутов"
  principle: time_priority_for_identity_only
}

rule attribute.truth {
  description: "Истинность атрибутов не определяется временем регистрации: при расхождении атрибут хранится как множество конкурирующих заявлений (claims) с провенансом (см. attribute.claims), каноническое значение выбирается явным правилом разрешения конфликтов (см. conflict.resolution)"
  principle: time_is_not_truth
}

rule work.manifestation_item {
  description: "Manifestation обязана ссылаться на Work (work_guid), Item — на Manifestation (manifestation_guid) и узел-владельца (owner_node_guid)"
  require: work_guid for entity_type == Manifestation
  require: manifestation_guid and owner_node_guid for entity_type == Item
  on_violation: reject_envelope
}

rule item.dedup {
  description: "Items разных узлов одной Manifestation не считаются дубликатами: это физические или локальные экземпляры; дедупликация выполняется на уровне Work и Manifestation"
  principle: dedup_at_work_manifestation_level
}

# ─────────────────────────────────────────────────────────────────────────
# 10. Заявления об атрибутах и разрешение конфликтов
# ─────────────────────────────────────────────────────────────────────────

rule attribute.claims {
  description: "Атрибут хранится как множество конкурирующих заявлений (claims) с провенансом, а не сворачивается в единое каноническое значение. При расхождении заявлений статус атрибута — unresolved: ошибка первого регистратора не «побеждает по умолчанию», дефолтной автоматической победы нет"
  action: keep_all_claims_with_provenance
  status: unresolved until resolution
}

rule conflict.resolution {
  description: "Каноническое значение выбирается явным правилом: (1) заявление становится canonical только после N≥2 независимых подтверждений от разных узлов; (2) действует окно оспаривания — в течение периода любой узел может подать встречное заявление с обоснованием (ссылка на источник, экспертиза); (3) при отсутствии оспаривания заявление первого регистратора становится дефолтным — как fallback, а не единственное правило"
  threshold: N >= 2 independent confirmations
  challenge_window: open for dispute with justification
  fallback: first_registrar_default_if_no_challenge
  note: "Меняет экономику Sybil-атаки: для продавливания ложного атрибута требуется N сговорившихся узлов, а не один"
}

rule rights.holder_confirmation {
  description: "Регистрация работ, созданных третьими лицами (например, студенческих работ), требует явного подтверждения правообладателя: rights_holder_confirmation (кто подтвердил, когда). Без подтверждения регистрация отклоняется; это не решает вопрос «кому принадлежит право», но исключает регистрацию чужой работы без ведома автора"
  require: rights_holder_confirmation for third-party works
  on_violation: reject_registration
}
}
