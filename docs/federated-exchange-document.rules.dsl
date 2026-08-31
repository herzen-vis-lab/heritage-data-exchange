# Heritage Data Exchange — правила протокола v0.0.4 (черновик)
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
  require: local_identifier if exchange_type == publish
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

rule dedup.candidate {
  description: "Первое сопоставление двух карточек создаёт связь со статусом candidate_match"
  trigger: dedup_request
  action: create Relation(status = candidate_match, asserted_by_node_guid = sender_node_guid)
}

rule dedup.confirm {
  description: "candidate_match переводится в confirmed_match только при согласии обеих сторон (обе карточки участвуют) или по решению авторитетного узла"
  condition: confirmed_by(source_node) AND confirmed_by(target_node)
  alt_condition: authority_decision(relation.authority)
  action: set Relation(status = confirmed_match)
}

rule dedup.reject {
  description: "Любая из сторон может отклонить связь; rejected_match фиксируется с указанием инициатора и не пересматривается без новых данных"
  trigger: dedup_response(reason != null)
  action: set Relation(status = rejected_match)
}

rule dedup.enrichment {
  description: "После confirmed_match атрибуты обеих карточек взаимно обогащаются; каждая сторона сохраняет провенанс своих атрибутов"
  action: merge_attributes(ak1, bk1) with provenance
  result: enrich_response от каждого узла-участника
}

rule dedup.propagation {
  description: "Изменения карточки распространяются конвертом enrich_response всем узлам, ссылающимся на объект"
  target: referenced_by(relation) ∪ subscribers(classification.group)
  on_violation: warn
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
  description: "receiver_node_guid опускается при broadcast-рассылке подписчикам группы классификатора"
  condition: receiver_node_guid == null implies publish_to_group(classification.group)
  on_violation: warn
}

rule envelope.types {
  description: "Семантика конвертов: publish — новые карточки; dedup_request — запрос проверки дубликатов; dedup_response — результаты проверки; enrich_response — обогащённые карточки и связи"
  constraint: exchange_type in [publish, dedup_request, dedup_response, enrich_response]
  on_violation: reject_envelope
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
