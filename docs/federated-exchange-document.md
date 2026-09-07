# Federated Exchange Document v0.1.0

Модель данных и правила протокола федеративного обмена объектами цифрового
культурного наследия в слабосвязанной сети независимых организаций.

Машиночитаемые и проверяемые артефакты:

- [JSON Schema модели данных](../schema/federated-exchange-document.schema.json)
- [JSON Schema конверта обмена](../schema/exchange-envelope.schema.json)
- [Правила протокола](federated-exchange-document.rules.dsl)
- [Проверяемый набор правил](../tests/README.md) — тесты и негативные фикстуры (CI)
- [Пример обмена А/Б](../examples/README.md)
- [Решения (ADR)](adr/)

Слои (v0.1.0): единица обмена между узлами — `ExchangeEnvelope`;
`FederatedExchangeDocument` (корневой тип) — полный снимок состояния
федерации: артефакт экспорта/резервирования, в обмене напрямую не участвует.
Решение зафиксировано в [ADR 0003](adr/0003-layering-and-versioning.md).

```mermaid
classDiagram
%% Work / Manifestation / Item — концептуальные уровни сущностей наследия.
%% В данных это НЕ отдельные классы: это значения entity_type карточки
%% DigitalObject, а work_guid / manifestation_guid / owner_node_guid —
%% поля той же карточки (см. JSON Schema). Отдельные классы ниже —
%% концептуальная проекция для читаемости.

class FederatedExchangeDocument {
   +UUID federated_exchange_document_guid
   +uri standard
   +semver version
   +datetime generated_at
}

class FederationNode {
   +UUID federation_node_guid
   +uri federation_node_url
   +datetime created_at
   +datetime modified_at
}

class DigitalObject {
   +UUID digital_object_guid
   +enum entity_type
   +uri digital_object_media_url
   +string local_identifier
   +uri record_url
   +rights_holder_confirmation
   +datetime created_at
   +datetime modified_at
}

class Classification {
   +string code
   +uri authority
   +UUID source_node_guid
   +UUID asserted_by_person_guid
   +datetime created_at
   +datetime modified_at
}

class License {
   +string code
   +uri authority
   +UUID source_node_guid
   +UUID asserted_by_person_guid
   +datetime created_at
   +datetime modified_at
}

class Claim {
   +scalar value
   +UUID source_node_guid
   +UUID asserted_by_person_guid
   +number confidence
   +enum status
   +datetime created_at
}

class Work {
   +UUID work_guid
   +datetime created_at
   +datetime modified_at
}

class Manifestation {
   +UUID manifestation_guid
   +uri digital_object_media_url
   +datetime created_at
   +datetime modified_at
}

class Item {
   +UUID item_guid
   +UUID owner_node_guid
   +string local_identifier
   +datetime created_at
   +datetime modified_at
}

%% Концептуальные уровни как значения entity_type карточки DigitalObject:
%% Work -- карточка с entity_type=Work (её digital_object_guid играет роль work_guid);
%% Manifestation -- карточка с entity_type=Manifestation и полем work_guid;
%% Item -- карточка с entity_type=Item и полями manifestation_guid + owner_node_guid.

class Metadata {
   +string key
   +scalar value
   +language language
   +uri authority
   +UUID source_node_guid
   +UUID asserted_by_person_guid
   +enum attribution_status
   +enum status
   +Claim[] claims
   +datetime created_at
   +datetime modified_at
}

class Person {
   +UUID person_guid
   +UUID owner_node_guid
   +string full_name
   +language language
}

class Relation {
   +UUID relation_guid
   +NodeType source_type
   +UUID source_guid
   +NodeType target_type
   +UUID target_guid
   +enum relation_type
   +uri authority
   +StatusType status
   +UUID asserted_by_node_guid
   +UUID confirmed_by_node_guid
   +datetime created_at
   +datetime modified_at
}

class NodeType {
   <<enumeration>>
   FederationNode
   DigitalObject
   Person
}

class StatusType {
   <<enumeration>>
   candidate_match
   confirmed_match
   rejected_match
}

FederatedExchangeDocument "1" --> "0..*" FederationNode : federation_nodes

FederationNode "1" --> "0..*" DigitalObject : digital_objects
FederationNode "1" --> "0..*" Person : persons
FederationNode "1" --> "0..*" Metadata : metadata
FederationNode "1" --> "0..*" Classification : classifications
FederationNode "1" --> "0..*" License : licenses
FederationNode "1" --> "0..*" Relation : relations

DigitalObject "1" --> "0..*" Metadata : metadata
DigitalObject "1" --> "0..*" Classification : classifications
DigitalObject "1" --> "0..*" License : licenses

Work "1" --> "0..*" Manifestation : manifestations
Manifestation "1" --> "0..*" Item : items

Person "1" --> "0..*" Metadata : metadata
Person "1" --> "0..*" Classification : classifications
```

Примечание (v0.1.0): провенанс атрибуции — каждый атрибут (`Metadata`) и
классификация могут указывать эксперта-атрибутора (`asserted_by_person_guid`,
ссылка на `Person`) и уровень верификации (`attribution_status`:
`unverified` / `expert_verified` / `authoritative`). Эксперты узлов
регистрируются и проходят верификацию уровня знаний; полная спецификация
полей — в [JSON Schema](../schema/federated-exchange-document.schema.json).

Персоны принадлежат узлам: в модели `Person` вложен в `FederationNode`
(каждый узел ведёт реестр своих экспертов), в конверте `persons` — контекст
конкретного обмена (набор персон, на которые ссылаются карточки), а не
глобальный реестр. Идентичность персоны — пара
`(owner_node_guid, person_guid)`; `asserted_by_person_guid` разрешается
в связке с `source_node_guid` атрибута. В конверте владелец персоны явный
(поле `owner_node_guid`; по умолчанию — `sender_node_guid` конверта).

Лицензии (`License`) задаются по аналогии с классификацией: код + `authority`.
`authority` может ссылаться на любой авторитетный источник лицензий (SPDX,
Creative Commons, реестры организаций); некоммерческая организация (НКО)
— один из возможных авторитетных источников, а не управляющий орган сети.
Поле `is_enabled_for_ai_using` в `Metadata` разрешает использование значения
атрибута в обучающих данных моделей ИИ; отсутствие флага означает запрет
(консервативный дефолт). Лицензия и флаг не отменяют друг друга: для
использования в обучающих данных нужны оба разрешения (правило `ai.license_gate`).

Сущности наследия моделируются через `entity_type` карточки (`DigitalObject`,
`Work`, `Manifestation`, `Item`). `Work` — абстрактная сущность, которую узлы
считают одним объектом описания; первый регистратор Work — первичный источник
атрибутных заявлений о ней, но не критерий их истинности. `Manifestation` —
конкретная реализация или форма представления Work (`work_guid`); `Item` —
локальный экземпляр Manifestation, учитываемый конкретным узлом
(`manifestation_guid`, `owner_node_guid`). Условные требования (Manifestation
⇒ `work_guid`; Item ⇒ `manifestation_guid` + `owner_node_guid`) выражены в
JSON Schema и проверяются валидатором. Work/Manifestation/Item не являются
отдельно адресуемыми сущностями: их роль выполняет карточка `DigitalObject`
с соответствующим `entity_type`, поэтому связи между сущностями наследия
указываются с типами концов `DigitalObject` (карточка несёт `entity_type`).
Различение уровней используется как практическая схема связывания объектов
и не претендует на полное воспроизведение библиографической онтологии FRBR
(уровень Expression сознательно не выделяется). Items разных узлов одной
Manifestation не считаются дубликатами; дедупликация выполняется на уровне
Work и Manifestation.

Приоритет по времени (первый регистратор) может использоваться как правило
идентичности и права управления локальной записью, но не как критерий
истинности атрибутов. При расхождении атрибут хранится как множество заявлений
(`Claim`) с провенансом и статусом (`unresolved` / `canonical` / `rejected`).
Каноническое значение выбирается явной политикой: порог независимых
подтверждений (по умолчанию N≥2; конфигурируется участниками), окно
оспаривания, fallback первого регистратора при отсутствии оспаривания.
Дедупликация (matching) и
принятие атрибутов (acceptance) — раздельные события протокола. Регистрация
работ, созданных третьими лицами, требует `rights_holder_confirmation`.

## Транспортный конверт (Exchange Envelope)

Модель данных выше описывает состояние федерации (снимок). Обмен между узлами
асинхронный и выполняется конвертами `ExchangeEnvelope` — обёрткой над
набором карточек объектов (`objects`), связей (`relations`) и персон
(`persons`). Конверт несёт метаданные протокола: версию и идентификаторы
узлов-отправителя и получателя.

Тип конверта один — `publish` (публикация состояния объекта). Режим
определяется полем `receiver_node_guid`:

| Режим | receiver_node_guid | Содержимое карточки |
|---|---|---|
| **Broadcast** | отсутствует | Полный снимок объекта: все атрибуты со всеми `source_node_guid`, известные отправителю; доставляется подписчикам группы классификатора |
| **Таргетированный (возврат вклада)** | заполнен (`= X`) | Только вклад получателя: атрибуты с `source_node_guid == X`, связи с участием X, минимальный контекст объекта (guid, media, local_identifier, record_url) |

Дедупликация и обогащение — локальные операции узлов: узел проверяет
полученные карточки на дубликаты в своей БД, добавляет атрибуты
(`source_node_guid` — свой) и публикует связи (`candidate_match` /
`confirmed_match` / `rejected_match`) теми же конвертами `publish`.
Тип связи — из базового словаря `relation_type` (`same_as`, `duplicate_of`);
расширенная семантика — через `authority`. Смена статуса связи публикуется
как новая версия той же `Relation` (тот же `relation_guid`, обновлённый
`modified_at`), подтвердивший узел фиксируется в `confirmed_by_node_guid` —
наблюдатели хранят историю решений по `relation_guid` (ADR 0002).
Получатель выполняет merge по провенансу: атрибуты с разными
`source_node_guid` не затирают друг друга. Мастер-запись не выделяется:
у каждого узла сохраняется собственная карточка объекта, карточки
связываются (`same_as`) и взаимно обогащаются.

Транспортный слой и механизм подписки на группы — предмет реализации и
отдельной публикации; целостность и подлинность конверта обеспечиваются
транспортным слоем (подпись, TLS). Бутстрап сети (кто ведёт реестр узлов и
классификаторов без центрального оператора) — см. ADR 0001.

Сценарий обмена между организациями А и Б (оцифровка → публикация →
проверка дубликатов → обогащение → подтверждение и возврат вклада) описан
в [примере](../examples/README.md), правила — в
[`federated-exchange-document.rules.dsl`](federated-exchange-document.rules.dsl).

```mermaid
sequenceDiagram
    autonumber
    participant A as Организация А (владелец)
    participant B as Организация Б (подписчик группы)
    Note over A: Оцифровка и атрибутирование:<br/>Work + Manifestation карточки, эксперты,<br/>source_node_guid/attribution_status
    A->>A: регистрация Work (первый регистратор)
    A-->>B: publish broadcast (полный снимок)<br/>receiver_node_guid отсутствует
    B->>B: локальная проверка на дубликаты (БК1)
    B-->>A: publish broadcast (снимок А+Б)<br/>+ Relation same_as candidate_match
    A->>A: merge по провенансу<br/>(атрибуты разных узлов не затираются)
    A-->>B: подтверждение: Relation confirmed_match<br/>(confirmed_by_node_guid, modified_at)
    A-->>B: publish targeted (receiver_node_guid = Б)<br/>возврат вклада: только атрибуты source_node_guid == Б<br/>+ встречное заявление по material (claims, unresolved)
    Note over B: Вклад принят: Б видит свои атрибуты<br/>и статус конфликта по material
```
