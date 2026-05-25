# ru-federated-cultural-ai-exchange.uml v.0.0.1
```mermaid
classDiagram

class HeritageDataExchange{
    +string standard
    +string version
    +datetime generated_at
}

class Organization {
    +string organization_guid
    +string name
    +string url
}

class RealObject {
    +string external_id
    +string authority
    +string url
}

class DigitalObject {
    +string digital_object_guid
    +string url
    +string[] tags
}

class Type {
    +string value
    +string authority
}

class Title {
    +string language
    +string value
}

class Description {
    +string language
    +string value
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

class DigitalObjectRelation {
    +string relation
    +string authority
    +string target_guid
}

class AI {
    +string model
    +datetime generated_at
    +string[] detected_objects
}

class Caption {
    +string language
    +string value
}

%% Relationships

HeritageDataExchange "1" --> "0..*" DigitalObject
DigitalObject "1" --> "0..*" Organization
DigitalObject "1" --> "0..*" Type
DigitalObject "1" --> "1" Metadata
Metadata "1" --> "1" Core
Metadata "1" --> "1" Rights
DigitalObject "1" --> "0..*" DigitalObjectRelation : source
DigitalObject "1" --> "0..1" RealObject : represents
DigitalObject "1" --> "0..1" AI
AI "1" --> "0..*" Caption
DigitalObject "1" --> "0..*"  Title
DigitalObject "1" --> "0..*"  Description
DigitalObjectRelation "1" --> "1" DigitalObject : target

```
