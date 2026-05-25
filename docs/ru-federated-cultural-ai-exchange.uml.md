classDiagram

class CulturalStandard {
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

CulturalStandard "1" --> "1" Organization
CulturalStandard "1" --> "many" CulturalObject

CulturalObject "1" --> "1" Type
CulturalObject "1" --> "1" Metadata
CulturalObject "1" --> "0..*" RelatedObject
CulturalObject "0..1" --> "1" AIAnnotation
CulturalObject "1" --> "1" LocalizedText : title
CulturalObject "1" --> "1" LocalizedText : description

Metadata "1" --> "1" Core
Metadata "1" --> "1" Rights

AIAnnotation "1" --> "1" Caption
