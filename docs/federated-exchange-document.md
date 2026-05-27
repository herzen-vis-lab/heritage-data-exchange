# Federated Exchange Document v0.0.3
* string - UTF-8 only
* datetime - ISO8601 UTC timestamps
* uri - absolute URI only
* Поля с названием language - BCP47 lowercase normalization
* omit null fields
* All UUID - globally unique (UUID v4), immutable, lowercase
* Each FederatedExchangeDocument represents an immutable export snapshot generated at generated_at.
* FederatedExchangeDocument.version: semver (MAJOR.MINOR.PATCH)
* FederatedExchangeDocument.standard = "https://github.com/herzen-vis-lab/heritage-data-exchange/blob/main/docs/federated-exchange-protocol.md"
* Classification определяется на уровне FederationNode и переиспользуется DigitalObject и Person
* Classification дедуплицируется через совпадение code + authority — не через Relation. authority должен быть глобально известным uri (например https://vocab.getty.edu/aat/). key должен соответствовать термину из словаря указанного в authority.
* Metadata entries attached to the same parent entity. MUST be unique by (key, language, authority). Metadata.value MUST be a JSON scalar:
- string
- number
- boolean

```mermaid
classDiagram

class FederatedExchangeDocument{
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
   +uri digital_object_media_url
   +datetime created_at
   +datetime modified_at
}

class Classification {
   +string code
   +uri authority
}

class Metadata {
   +string key
   +json value
   +string language
   +uri authority
}

class Person {
   +UUID person_guid
   +string full_name
   +string language
}

class Relation {
   +NodeType source_type
   +UUID source_guid
   +NodeType target_type
   +UUID target_guid
   +string relation
   +uri authority
}

class NodeType {
    <<enumeration>>
    FederationNode
    DigitalObject
    Person
}

%% Relationships

FederatedExchangeDocument "1" --> "0..*" FederationNode 
FederationNode "1" --> "0..*" DigitalObject
FederationNode "1" --> "0..*" Person : person
FederationNode "1" --> "0..*" Metadata : metadata
FederationNode "1" --> "0..*" Classification : classification
FederationNode "1" --> "0..*"  Relation : relation
DigitalObject "1" --> "0..*"  Metadata : metadata
DigitalObject "1" --> "0..*" Classification : classification
Person "1" --> "0..*"  Metadata : metadata
Person "1" --> "0..*" Classification : classification
```
