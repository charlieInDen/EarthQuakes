# Loading and Displaying a Large Data Feed

Consume data in the background, and lower memory usage by batching imports and preventing duplicate records in the Core Data store.

## Overview
This sample app shows a list of earthquakes recorded in the United States in the past 30 days by consuming a U. S. Geological Survey (USGS) real time data feed.

Press the app’s refresh button to load the USGS JSON feed on the URLSession’s default delegate queue, which is a serial operations queue running in the background. Once the feed downloads, continue working on this queue to import the large number of feed elements to the store without blocking the main queue.

## Import Data in the Background

To import data in the background, you need two managed object contexts: a main queue context to provide data to the user interface, and a private queue context to perform the import on a background queue. 

Create a main queue context by setting up your Core Data stack using [`NSPersistentContainer`](https://developer.apple.com/documentation/coredata/nspersistentcontainer), which initializes a main queue context in its [`viewContext`](https://developer.apple.com/documentation/coredata/nspersistentcontainer/1640622-viewcontext) property. 

``` swift
let container = NSPersistentContainer(name: "Earthquakes")
```

Create a private queue context by calling the persistent container’s [`newBackgroundContext()`](https://developer.apple.com/documentation/coredata/nspersistentcontainer/1640581-newbackgroundcontext) method.

``` swift
let taskContext = persistentContainer.newBackgroundContext()
```

When the feed download finishes, use the task context to consume the feed in the background. Wrap your work in a [`performAndWait()`](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/1506364-performandwait) block. 

``` swift
// taskContext.performAndWait runs on the URLSession's delegate queue
// so it won’t block the main thread.
taskContext.performAndWait {
```

For more information about working with concurrency, see [`NSManagedObjectContext`](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext#1654001).

## Update the User Interface

To show the imported data in the user interface, merge it from the private queue into the main queue.

Set the `viewContext`’s [`automaticallyMergesChangesFromParent`](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/1845237-automaticallymergeschangesfrompa) property to `true`.

``` swift
// Merge the changes from other contexts automatically.
container.viewContext.automaticallyMergesChangesFromParent = true
```

Both contexts are connected to the same [`persistentStoreCoordinator`](https://developer.apple.com/documentation/coredata/nspersistentcontainer/1640567-persistentstorecoordinator), which serves as their parent for data merging purposes. This is more efficient than merging between parent and child contexts.

When the background context saves, Core Data observes the changes to the store and merges them into the `viewContext` automatically. Then [`NSFetchedResultsController`](https://developer.apple.com/documentation/coredata/nsfetchedresultscontroller) observes changes to the `viewContext`, and updates the user interface accordingly.

Finally, dispatch any user interface state updates back to the main queue.

``` swift
dataProvider.fetchQuakes { error in
    DispatchQueue.main.async {
        
        // Update the spinner and refresh button states.
        self.navigationItem.rightBarButtonItem?.isEnabled = true
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
        self.spinner.stopAnimating()

        // Show an alert if there was an error.
        guard let error = error else { return }
        let alert = UIAlertController(title: "Fetch quakes error!",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
}
```

## Work in Batches to Lower Your Memory Footprint

Core Data caches the objects that are fetched or created in a context, to avoid a round trip to the store file when these objects are needed again. However, your app’s memory footprint grows as you import more and more objects. To avoid a low memory warning or termination by iOS, perform the import in batches and reset the context after each batch.

Split the import into batches by dividing the total number of records by your chosen batch size.

``` swift
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
```

Reset the context after importing each batch by calling [`reset()`](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/1506807-reset).

``` swift
taskContext.reset()
```

## Prevent Duplicate Data in the Store

Every time you refresh the feed, the data downloaded from the remote server contains all earthquake records for the past month, so it can have many duplicates of data you’ve already imported. To avoid creating duplicate records, you constrain an attribute, or combination of attributes, to be unique across all instances. 

The `code` attribute uniquely identifies an earthquake record, so constraining the `Quake` entity on `code` ensures that no two stored records have the same `code` value.

Select the `Quake` entity in the data model editor. In the data model inspector, add a new constraint by clicking the + button under the Constraints list. A constraint placeholder appears.

```
comma, separated, properties
```

Double-click the placeholder to edit it. Enter the name of the attribute (or comma-separated list of attributes) to serve as unique constraints on the entity. 

```
code
```

When saving a new record, the store now checks whether any record already exists with the same value for the constrained attribute. In the case of a conflict, an [`NSMergeByPropertyObjectTrump`](https://developer.apple.com/documentation/coredata/nsmergebypropertyobjecttrumpmergepolicy) policy comes into play, and the new record overwrites all fields in the existing record.
