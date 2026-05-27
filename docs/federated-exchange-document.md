# Federated Exchange Document v0.0.3
%%: UUID - globally unique (UUID v4), immutable

%%: FederatedExchangeDocument.version: semver (MAJOR.MINOR.PATCH)

%%: FederatedExchangeDocument.standard = "https://github.com/herzen-vis-lab/heritage-data-exchange/blob/main/docs/federated-exchange-protocol.md"

%%: MetadataRoleType - каждая конкретная FederationNode может расширять данный справочник

%%: Classification определяется на уровне FederationNode и переиспользуется DigitalObject и Person

%%: Classification дедуплицируется через совпадение code + authority — не через Relation. 

%%: authority должен быть глобально известным URI (например https://vocab.getty.edu/aat/).

%%: key должен соответствовать термину из словаря указанного в authority.


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
   +DataType datatype
   +string value
   +string language
   +MetadataRoleType role
   +uri authority
}

class Person {
   +UUID person_guid
   +string person_language
   +string family_name
   +string given_name
   +string middle_name
}

class Relation {
   +NodeType source_type
   +UUID source_guid
   +NodeType target_type
   +UUID target_guid
   +RelationType relation
   +uri authority
}

class NodeType {
    <<enumeration>>
    FederationNode
    DigitalObject
    Person
}

class RelationType {
   <<enumeration>>
   derived_from
   same_as
   part_of
   has_part
   created_by
   modified_by
}

class MetadataRoleType {
   <<enumeration>>
   name
   title
   description
}

class DataType {
   <<enumeration>>
   string
   number
   boolean
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
