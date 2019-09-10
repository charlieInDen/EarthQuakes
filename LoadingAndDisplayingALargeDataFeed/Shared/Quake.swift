/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An NSManagedObject subclass for the Quake entity.
*/

import CoreData

// MARK: - Core Data

/**
 Managed object subclass for the Quake entity.
 */
class Quake: NSManagedObject {
    
    // The characteristics of a quake.
    @NSManaged var magnitude: Float
    @NSManaged var place: String
    @NSManaged var time: Date
    
    // A unique identifier for removing duplicates. Constrain
    // the Quake entity on this attribute in the data model editor.
    @NSManaged var code: String
    
    /**
     Updates a Quake instance with the values from a QuakeProperties.
     */
    func update(with quakeProperties: QuakeProperties) throws {
        
        // Update the quake only if all provided properties have values.
        guard let newCode = quakeProperties.code,
            let newMagnitude = quakeProperties.mag,
            let newPlace = quakeProperties.place,
            let newTime = quakeProperties.time else {
                throw QuakeError.missingData
        }
        code = newCode
        magnitude = newMagnitude
        place = newPlace
        time = Date(timeIntervalSince1970: newTime / 1000.0)
    }
}

// MARK: - Codable

/**
 A struct for decoding JSON with the following structure:

 "{
     "features":[{
        "properties":{
             "mag":1.9,
             "place":"21km ENE of Honaunau-Napoopoo, Hawaii",
             "time":1539187727610,"updated":1539187924350,
             "code":"70643082"
        }
     }]
 }"
 
 Stores an array of decoded QuakeProperties for later use in
 creating or updating Quake instances.
*/
struct GeoJSON: Decodable {
    private enum RootCodingKeys: String, CodingKey {
        case features
    }
    private enum FeatureCodingKeys: String, CodingKey {
        case properties
    }
    
    // A QuakeProperties array of decoded Quake data.
    var quakePropertiesArray = [QuakeProperties]()
    
    init(from decoder: Decoder) throws {
        let rootContainer = try decoder.container(keyedBy: RootCodingKeys.self)
        var featuresContainer = try rootContainer.nestedUnkeyedContainer(forKey: .features)
        
        while featuresContainer.isAtEnd == false {
            let propertiesContainer = try featuresContainer.nestedContainer(keyedBy: FeatureCodingKeys.self)
            
            // Decodes a single quake from the data, and appends it to the array.
            let properties = try propertiesContainer.decode(QuakeProperties.self, forKey: .properties)
            quakePropertiesArray.append(properties)
        }
    }
}

/**
 A struct encapsulating the properties of a Quake. All members are
 optional in case they are missing from the data.
 */
struct QuakeProperties: Decodable {
    let mag: Float?         // 1.9
    let place: String?      // "21km ENE of Honaunau-Napoopoo, Hawaii"
    let time: Double?       // 1539187727610
    let code: String?       // "70643082"
}
