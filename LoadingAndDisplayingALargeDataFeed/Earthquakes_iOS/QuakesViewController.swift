/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A UIViewController subclass to manage a table view that displays a collection of quakes.
*/

import UIKit
import CoreData

class QuakesViewController: UITableViewController {
    
    // MARK: Core Data
    
    /**
     The QuakesProvider that fetches quake data, saves it to Core Data,
     and serves it to this table view.
     */
    private lazy var dataProvider: QuakesProvider = {
        
        let provider = QuakesProvider()
        provider.fetchedResultsControllerDelegate = self
        return provider
    }()
    
    /**
     Fetches the remote quake feed when the refresh button is tapped.
     */
    @IBAction func fetchQuakes(_ sender: UIBarButtonItem) {
        
        // Ensure the button can't be pressed again before the fetch is complete.
        navigationItem.rightBarButtonItem?.isEnabled = false
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        spinner.startAnimating()

        // Use the QuakesProvider to fetch quake data. On completion,
        // handle general UI updates and error alerts on the main queue.
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
    }
    
    // MARK: View
    
    private lazy var spinner: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .whiteLarge)
        indicator.color = .gray
        indicator.hidesWhenStopped = true
        return indicator
    }()
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if spinner.superview == nil, let superView = tableView.superview {
            superView.addSubview(spinner)
            superView.bringSubviewToFront(spinner)
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.centerXAnchor.constraint(equalTo: superView.centerXAnchor).isActive = true
            spinner.centerYAnchor.constraint(equalTo: superView.centerYAnchor).isActive = true
        }
    }
}

// MARK: - UITableViewDataSource

extension QuakesViewController {
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "QuakeCell", for: indexPath) as? QuakeCell else {
            print("Error: tableView.dequeueReusableCell doesn'return a QuakeCell!")
            return QuakeCell()
        }
        guard let quake = dataProvider.fetchedResultsController.fetchedObjects?[indexPath.row] else { return cell }
        
        cell.configure(with: quake)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataProvider.fetchedResultsController.fetchedObjects?.count ?? 0
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension QuakesViewController: NSFetchedResultsControllerDelegate {
    
    /**
     Reloads the table view when the fetched result controller's content changes.
     */
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.reloadData()
    }
}
