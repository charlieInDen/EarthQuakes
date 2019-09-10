/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class to fetch data from the remote server and save it to the Core Data store.
*/
import CoreData

class QuakesProvider {

    // MARK: - USGS Data
    
    /**
     Geological data provided by the U.S. Geological Survey (USGS). See ACKNOWLEDGMENTS.txt for additional details.
     */
    let earthquakesFeed = "http://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_month.geojson"
    
    // MARK: - Core Data
    
    /**
     A persistent container to set up the Core Data stack.
    */
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Earthquakes")
        
        container.loadPersistentStores { storeDesription, error in
            guard error == nil else {
                fatalError("Unresolved error \(error!)")
            }
        }

        // Merge the changes from other contexts automatically.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
        return container
    }()
    
    /**
     Fetches the earthquake feed from the remote server, and imports it into Core Data.
     
     Because this server does not offer a secure communication channel, this example
     uses an http URL and adds "earthquake.usgs.gov" to the "NSExceptionDomains" value
     in the apps's info.plist. When you commmunicate with your own servers, or when
     the services you use offer a secure communication option, you should always
     prefer to use https.
    */
    func fetchQuakes(completionHandler: @escaping (Error?) -> Void) {
        
        // Create a URL to load, and a URLSession to load it.
        guard let jsonURL = URL(string: earthquakesFeed) else {
            completionHandler(QuakeError.urlError)
            return
        }
        let session = URLSession(configuration: .default)
        
        // Create a URLSession dataTask to fetch the feed.
        let task = session.dataTask(with: jsonURL) { data, _, error in

            // Alert the user if no data comes back.
            guard let data = data else {
                completionHandler(QuakeError.networkUnavailable)
                return
            }
            
            // Decode the JSON and import it into Core Data.
            do {
                // Decode the JSON into codable type GeoJSON.
                let decoder = JSONDecoder()
                let geoJSON = try decoder.decode(GeoJSON.self, from: data)
                
                // Import the GeoJSON into Core Data.
                try self.importQuakes(from: geoJSON)
                
            } catch {
                // Alert the user if data cannot be digested.
                completionHandler(QuakeError.wrongDataFormat)
                return
            }
            completionHandler(nil)
        }
        // Start the task.
        task.resume()
    }
    
    /**
     Imports a JSON dictionary into the Core Data store on a private queue,
     processing the record in batches to avoid a high memory footprint.
    */
    private func importQuakes(from geoJSON: GeoJSON) throws {
        
        guard !geoJSON.quakePropertiesArray.isEmpty else { return }
        
        // Create a private queue context.
        let taskContext = persistentContainer.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        // Set unused undoManager to nil for macOS (it is nil by default on iOS)
        // to reduce resource requirements.
        taskContext.undoManager = nil
                
        // Process records in batches to avoid a high memory footprint.
        let batchSize = 256
        let count = geoJSON.quakePropertiesArray.count
        
        // Determine the total number of batches.
        var numBatches = count / batchSize
        numBatches += count % batchSize > 0 ? 1 : 0
        
        for batchNumber in 0 ..< numBatches {
            
            // Determine the range for this batch.
            let batchStart = batchNumber * batchSize
            let batchEnd = batchStart + min(batchSize, count - batchNumber * batchSize)
            let range = batchStart..<batchEnd
            
            // Create a batch for this range from the decoded JSON.
            let quakesBatch = Array(geoJSON.quakePropertiesArray[range])
            
            // Stop the entire import if any batch is unsuccessful.
            if !importOneBatch(quakesBatch, taskContext: taskContext) {
                return
            }
        }
    }
    
    /**
     Imports one batch of quakes, creating managed objects from the new data,
     and saving them to the persistent store, on a private queue. After saving,
     resets the context to clean up the cache and lower the memory footprint.
     
     NSManagedObjectContext.performAndWait doesn't rethrow so this function
     catches throws within the closure and uses a return value to indicate
     whether the import is successful.
    */
    private func importOneBatch(_ quakesBatch: [QuakeProperties], taskContext: NSManagedObjectContext) -> Bool {
        
        var success = false

        // taskContext.performAndWait runs on the URLSession's delegate queue
        // so it won’t block the main thread.
        taskContext.performAndWait {
            // Create a new record for each quake in the batch.
            for quakeData in quakesBatch {
                
                // Create a Quake managed object on the private queue context.
                guard let quake = NSEntityDescription.insertNewObject(forEntityName: "Quake", into: taskContext) as? Quake else {
                    print(QuakeError.creationError.localizedDescription)
                    return
                }
                // Populate the Quake's properties using the raw data.
                do {
                    try quake.update(with: quakeData)
                } catch QuakeError.missingData {
                    // Delete invalid Quake from the private queue context.
                    print(QuakeError.missingData.localizedDescription)
                    taskContext.delete(quake)
                } catch {
                    print(error.localizedDescription)
                }
            }
            
            // Save all insertions and deletions from the context to the store.
            if taskContext.hasChanges {
                do {
                    try taskContext.save()
                } catch {
                    print("Error: \(error)\nCould not save Core Data context.")
                    return
                }
                // Reset the taskContext to free the cache and lower the memory footprint.
                taskContext.reset()
            }
            
            success = true
        }
        return success
    }
    
    // MARK: - NSFetchedResultsController
    
    /**
     A fetched results controller delegate to give consumers a chance to update
     the user interface when content changes.
     */
    weak var fetchedResultsControllerDelegate: NSFetchedResultsControllerDelegate?
    
    /**
     A fetched results controller to fetch Quake records sorted by time.
     */
    lazy var fetchedResultsController: NSFetchedResultsController<Quake> = {
        
        // Create a fetch request for the Quake entity sorted by time.
        let fetchRequest = NSFetchRequest<Quake>(entityName: "Quake")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "time", ascending: false)]
        
        // Create a fetched results controller and set its fetch request, context, and delegate.
        let controller = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                    managedObjectContext: persistentContainer.viewContext,
                                                    sectionNameKeyPath: nil, cacheName: nil)
        controller.delegate = fetchedResultsControllerDelegate
        
        // Perform the fetch.
        do {
            try controller.performFetch()
        } catch {
            fatalError("Unresolved error \(error)")
        }
        
        return controller
    }()
}
