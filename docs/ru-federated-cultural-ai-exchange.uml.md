# Ru-federated-cultural-ai-exchange.uml v.0.0.1
```mermaid
classDiagram

class Heritage-data-exchange{
    +string standard
    +string version
    +datetime generated_at
}

class Organization {
    +string organization_guid
    +string name
    +string url
}

class CulturalObject {
    +string object_guid
    +string url
    +string[] tags
}

class Type {
    +string value
    +string type_parent
    +string type_parent_vocabulary
}

class LocalizedText {
    +string ru
    +string en
}

class Metadata {
    +Core core
    +Rights rights
}

class Core {
    +string creator
    +string date_created
    +string[] subject
    +string source
    +string coverage
    +string inventory_number
}

class Rights {
    +string status
    +string license
    +string license_url
    +string holder
}

class RelatedObject {
    +string relation
    +string object_guid
    +string organization_guid
}

class AIAnnotation {
    +string model
    +datetime generated_at
    +string[] detected_objects
}

class Caption {
    +string ru
    +string en
}

%% Relationships

Heritage-data-exchange "1" --> "1" Organization
Heritage-data-exchange "1" --> "many" CulturalObject

CulturalObject "1" --> "1" Type
CulturalObject "1" --> "1" Metadata
CulturalObject "1" --> "0..*" RelatedObject
CulturalObject "0..1" --> "1" AIAnnotation
CulturalObject "1" --> "1" LocalizedText : title
CulturalObject "1" --> "1" LocalizedText : description

Metadata "1" --> "1" Core
Metadata "1" --> "1" Rights

AIAnnotation "1" --> "1" Caption
```
