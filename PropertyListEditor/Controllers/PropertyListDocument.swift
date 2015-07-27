//
//  PropertyListDocument.swift
//  PropertyListEditor
//
//  Created by Prachi Gauriar on 7/1/2015.
//  Copyright © 2015 Quantum Lens Cap. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Cocoa


/// `PropertyListDocument` is the primary controller class in this application. It manages the 
/// Property List document windows and the backing property list items in the data model.
class PropertyListDocument: NSDocument, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// The `TableColumn` enum is used to enumerate the different `NSTableColumns` that the
    /// instance’s outline view has. Whenever a table column is added to the outline view, a
    /// corresponding case should be added to this enum. Additionally, the table column’s
    /// identifier should be the same as the case name in this enum. The value of using this
    /// approach is that the compiler ensures that all table column cases are handled by the
    /// code. 
    private enum TableColumn: String {
        case Key, Type, Value
    }


    /// The instance’s outline view.
    @IBOutlet weak var propertyListOutlineView: NSOutlineView!

    /// The prototype cell for the Key column’s text field cell.
    @IBOutlet weak var keyTextFieldPrototypeCell: NSTextFieldCell!

    /// The prototypical cell for the Type column’s pop-up button cell.
    @IBOutlet weak var typePopUpButtonPrototypeCell: NSPopUpButtonCell!

    /// The prototypical cell for the Value column’s text field cell.
    @IBOutlet weak var valueTextFieldPrototypeCell: NSTextFieldCell!


    /// The instance’s property list tree.
    private var tree: PropertyListTree! {
        didSet {
            self.propertyListOutlineView?.reloadData()
        }
    }


    override init() {
        self.tree = PropertyListTree()
        super.init()
    }


    deinit {
        // Failing to unset the data source here results in a stray delegate message 
        // sent to the zombie PropertyListDocument. While there may be a more correct
        // solution, I’ve yet to find it
        self.propertyListOutlineView?.setDataSource(nil)
        self.propertyListOutlineView?.setDelegate(nil)
    }


    // MARK: - NSDocument Methods

    override var windowNibName: String? {
        return "PropertyListDocument"
    }


    override func windowControllerDidLoadNib(aController: NSWindowController) {
        super.windowControllerDidLoadNib(aController)
        self.propertyListOutlineView.expandItem(nil, expandChildren: true)
    }


    override func dataOfType(typeName: String) throws -> NSData {
        return self.tree.rootItem.propertyListXMLDocumentData()
    }


    override func readFromData(data: NSData, ofType typeName: String) throws {
        var format: NSPropertyListFormat = .XMLFormat_v1_0
        let propertyListObject = try NSPropertyListSerialization.propertyListWithData(data, options: [], format: &format) as! PropertyListItemConvertible

        do {
            let rootItem: PropertyListItem
            if format == .XMLFormat_v1_0 {
                rootItem = try PropertyListXMLReader(XMLData: data).readData()
            } else {
                rootItem = try propertyListObject.propertyListItem()
            }

            self.tree = PropertyListTree(rootItem: rootItem)
        } catch let error {
            print("Error reading document: \(error)")
            throw error
        }
    }


    // MARK: - Outline View Data Source

    func outlineView(outlineView: NSOutlineView, numberOfChildrenOfItem item: AnyObject?) -> Int {
        if item == nil {
            return 1
        }

        guard let treeNode = item as? PropertyListTreeNode else {
            assert(false, "item must be a PropertyListTreeNode")
        }

        return treeNode.numberOfChildren
    }


    func outlineView(outlineView: NSOutlineView, isItemExpandable item: AnyObject) -> Bool {
        guard let treeNode = item as? PropertyListTreeNode else {
            assert(false, "item must be a PropertyListTreeNode")
        }

        return treeNode.isExpandable
    }


    func outlineView(outlineView: NSOutlineView, child index: Int, ofItem item: AnyObject?) -> AnyObject {
        if item == nil {
            return self.tree.rootNode
        }

        guard let treeNode = item as? PropertyListTreeNode else {
            assert(false, "item must be a PropertyListTreeNode")
        }

        return treeNode.childAtIndex(index)
    }


    func outlineView(outlineView: NSOutlineView, objectValueForTableColumn tableColumn: NSTableColumn?, byItem item: AnyObject?) -> AnyObject? {
        guard let tableColumnIdentifier = tableColumn?.identifier, treeNode = item as? PropertyListTreeNode else {
            return nil
        }

        guard let tableColumn = TableColumn(rawValue: tableColumnIdentifier) else {
            assert(false, "invalid table column identifier \(tableColumnIdentifier)")
        }

        switch tableColumn {
        case .Key:
            return self.keyOfTreeNode(treeNode)
        case .Type:
            return self.typeOfTreeNode(treeNode)
        case .Value:
            return self.valueOfTreeNode(treeNode)
        }
    }


    func outlineView(outlineView: NSOutlineView, setObjectValue object: AnyObject?, forTableColumn tableColumn: NSTableColumn?, byItem item: AnyObject?) {
        guard let tableColumnIdentifier = tableColumn?.identifier, let treeNode = item as? PropertyListTreeNode else {
            return
        }

        guard let tableColumn = TableColumn(rawValue: tableColumnIdentifier) else {
            assert(false, "invalid table column identifier \(tableColumnIdentifier)")
        }

        guard let propertyListObject = object as? PropertyListItemConvertible else {
            assert(false, "object value (\(object)) is not a property list object")
        }

        switch tableColumn {
        case .Key:
            if !self.setKey(object as! String, ofTreeNode: treeNode) {
                NSBeep()
            }
        case .Type:
            let type = PropertyListType(typePopUpMenuItemIndex: object as! Int)!
            self.setType(type, ofTreeNode: treeNode)
        case .Value:
            let item: PropertyListItem

            if case let nodeItem = treeNode.item,
                // If the value was set via a pop up button
                let valueConstraint = nodeItem.valueConstraint,
                case let .ValueArray(valueArray) = valueConstraint,
                let popUpButtonMenuItemIndex = object as? Int {
                    item = try! valueArray[popUpButtonMenuItemIndex].value.propertyListItem()
            } else {
                // Otherwise, just create a property list item
                item = try! propertyListObject.propertyListItem()
            }

            self.setValue(item, ofTreeNode: treeNode)
        }
    }


    // MARK: - Outline View Delegate

    func outlineView(outlineView: NSOutlineView, dataCellForTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> NSCell? {
        guard let tableColumnIdentifier = tableColumn?.identifier, treeNode = item as? PropertyListTreeNode else {
            return nil
        }

        guard let tableColumn = TableColumn(rawValue: tableColumnIdentifier) else {
            assert(false, "invalid table column identifier \(tableColumnIdentifier)")
        }

        switch tableColumn {
        case .Key:
            let cell = self.keyTextFieldPrototypeCell.copy() as! NSTextFieldCell

            if let parentNode = treeNode.parentNode {
                cell.editable = parentNode.item.propertyListType == .DictionaryType
            } else {
                cell.editable = false
            }

            return cell
        case .Type:
            return self.typePopUpButtonPrototypeCell.copy() as! NSPopUpButtonCell
        case .Value:
            return self.valueCellForTreeNode(treeNode)
        }
    }


    func outlineView(outlineView: NSOutlineView, shouldEditTableColumn tableColumn: NSTableColumn?, item: AnyObject) -> Bool {
        guard let tableColumnIdentifier = tableColumn?.identifier, treeNode = item as? PropertyListTreeNode else {
            return false
        }

        guard let tableColumn = TableColumn(rawValue: tableColumnIdentifier) else {
            assert(false, "invalid table column identifier \(tableColumnIdentifier)")
        }

        switch tableColumn {
        case .Key:
            guard let parentItem = treeNode.parentNode?.item else {
                return false
            }

            return parentItem.propertyListType == .DictionaryType
        case .Type:
            return true
        case .Value:
            return !treeNode.item.isCollection
        }
    }


    private func valueCellForTreeNode(treeNode: PropertyListTreeNode) -> NSCell {
        let item = treeNode.item

        if item.isCollection {
            let cell = self.valueTextFieldPrototypeCell.copy() as! NSTextFieldCell
            cell.textColor = NSColor.disabledControlTextColor()
            return cell
        }

        guard let valueConstraint = item.valueConstraint else {
            return self.valueTextFieldPrototypeCell.copy() as! NSTextFieldCell
        }

        switch valueConstraint {
        case let .Formatter(formatter):
            let cell = self.valueTextFieldPrototypeCell.copy() as! NSTextFieldCell
            cell.formatter = formatter
            return cell
        case let .ValueArray(validValues):
            return self.popUpButtonCellWithValidValues(validValues)
        }
    }


    private func popUpButtonCellWithValidValues(validValues: [PropertyListValidValue]) -> NSPopUpButtonCell {
        let cell = NSPopUpButtonCell()
        cell.bordered = false
        cell.font = NSFont.systemFontOfSize(NSFont.systemFontSizeForControlSize(.SmallControlSize))
        
        for validValue in validValues {
            cell.addItemWithTitle(validValue.localizedDescription)
            cell.menu!.itemArray.last!.representedObject = validValue.value
        }
        
        return cell
    }


    // MARK: - UI Validation

    override func validateUserInterfaceItem(userInterfaceItem: NSValidatedUserInterfaceItem) -> Bool {
        let selectors = Set<Selector>(arrayLiteral: "addChild:", "addSibling:", "deleteItem:")
        let action = userInterfaceItem.action()

        guard selectors.contains(action) else {
            return super.validateUserInterfaceItem(userInterfaceItem)
        }

        let outlineView = self.propertyListOutlineView
        let treeNode: PropertyListTreeNode
        if outlineView.numberOfSelectedRows == 0 {
            treeNode = self.tree.rootNode
        } else {
            treeNode = outlineView.itemAtRow(outlineView.selectedRow) as! PropertyListTreeNode
        }

        switch action {
        case "addChild:":
            return treeNode.item.isCollection
        case "addSibling:", "deleteItem:":
            return !treeNode.isRootNode
        default:
            return false
        }
    }


    // MARK: - Action Methods

    @IBAction func addChild(sender: AnyObject?) {
        var rowIndex = self.propertyListOutlineView.selectedRow
        if rowIndex == -1 {
            rowIndex = 0
        }

        let treeNode = self.propertyListOutlineView.itemAtRow(rowIndex) as! PropertyListTreeNode
        guard treeNode.isExpandable else {
            NSLog("Received addChild: on unexpandable item. Ignoring…")
            return
        }

        self.insertItem(self.itemForAdding(), atIndex: treeNode.numberOfChildren, inTreeNode: treeNode)
        self.editTreeNode(treeNode.lastChild!)
    }


    @IBAction func addSibling(sender: AnyObject?) {
        let selectedRow = self.propertyListOutlineView.selectedRow

        guard selectedRow != -1,
            let selectedNode = self.propertyListOutlineView.itemAtRow(selectedRow) as? PropertyListTreeNode,
            let parentNode = selectedNode.parentNode where parentNode.item.isCollection else {
                return
        }

        let index: Int! = selectedNode.index
        self.insertItem(self.itemForAdding(), atIndex: index + 1, inTreeNode: parentNode)
        self.editTreeNode(parentNode.childAtIndex(index + 1))
    }


    @IBAction func deleteItem(sender: AnyObject?) {
        let selectedRow = self.propertyListOutlineView.selectedRow

        guard selectedRow != -1,
            let selectedTreeNode = self.propertyListOutlineView.itemAtRow(selectedRow) as? PropertyListTreeNode,
            let parentTreeNode = selectedTreeNode.parentNode where parentTreeNode.item.isCollection else {
                return
        }

        let index: Int! = selectedTreeNode.index
        self.removeItemAtIndex(index, inTreeNode: parentTreeNode)
    }


    private func editTreeNode(treeNode: PropertyListTreeNode) {
        let rowIndex = self.propertyListOutlineView.rowForItem(treeNode)

        let column: TableColumn
        if treeNode.isRootNode {
            column = .Value
        } else {
            column = treeNode.parentNode!.item.propertyListType == .DictionaryType ? .Key : .Value
        }

        let columnIndex = self.propertyListOutlineView.tableColumns.indexOf { $0.identifier == column.rawValue }
        self.propertyListOutlineView.selectRowIndexes(NSIndexSet(index: rowIndex), byExtendingSelection: false)
        self.propertyListOutlineView.editColumn(columnIndex!, row: rowIndex, withEvent: nil, select: true)

    }


    // MARK: - Manipulating Tree Nodes Items

    private func keyOfTreeNode(treeNode: PropertyListTreeNode) -> NSString? {
        guard let index = treeNode.index else {
            return NSLocalizedString("PropertyListDocument.RootNodeKey", comment: "Key for root node")
        }

        // Parent node will be non-nil if index is non-nil
        switch treeNode.parentNode!.item {
        case .ArrayItem:
            let formatString = NSLocalizedString("PropertyListDocument.ArrayItemKeyFormat", comment: "Format string for array item node key")
            return NSString.localizedStringWithFormat(formatString, index)
        case let .DictionaryItem(dictionary):
            return dictionary.elementAtIndex(index).key
        default:
            return nil
        }
    }


    private func setKey(key: String, ofTreeNode treeNode: PropertyListTreeNode) -> Bool {
        guard let parentNode = treeNode.parentNode, index = treeNode.index else {
            return false
        }

        switch parentNode.item {
        case var .DictionaryItem(dictionary):
            guard !dictionary.containsKey(key) else {
                return false
            }

            dictionary.setKey(key, atIndex: index)
            self.setItem(.DictionaryItem(dictionary), ofTreeNodeAtIndexPath: parentNode.indexPath)
            return true
        default:
            return false
        }
    }


    private func typeOfTreeNode(treeNode: PropertyListTreeNode) -> Int {
        return treeNode.item.propertyListType.typePopUpMenuItemIndex
    }


    private func setType(type: PropertyListType, ofTreeNode treeNode: PropertyListTreeNode) {
        let wasCollection = treeNode.item.isCollection
        let value = treeNode.item.propertyListItemByConvertingToType(type)
        let isCollection = value.isCollection

        // We only need child regeneration if we changed from being a scalar to a collection or vice versa.
        // If we changed types from one collection to another, we convert the children automatically, so
        // we will have the right number of nodes.
        self.setValue(value, ofTreeNode: treeNode, needsChildRegeneration: wasCollection != isCollection)
    }


    private func valueOfTreeNode(treeNode: PropertyListTreeNode) -> AnyObject {
        switch treeNode.item {
        case .ArrayItem:
            let formatString = NSLocalizedString("PropertyListDocument.ArrayValueFormat", comment: "Format string for values of arrays")
            return NSString.localizedStringWithFormat(formatString, treeNode.numberOfChildren)
        case .DictionaryItem:
            let formatString = NSLocalizedString("PropertyListDocument.DictionaryValueFormat", comment: "Format string for values of dictionaries")
            return NSString.localizedStringWithFormat(formatString, treeNode.numberOfChildren)
        default:
            return treeNode.item.propertyListObjectValue
        }
    }
    

    private func setValue(newValue: PropertyListItem, ofTreeNode treeNode: PropertyListTreeNode, needsChildRegeneration: Bool = false) {
        guard let parentNode = treeNode.parentNode else {
            let nodeOperation: TreeNodeOperation? = needsChildRegeneration ? .RegenerateChildren : nil
            self.setItem(newValue, ofTreeNodeAtIndexPath: self.tree.rootNode.indexPath, nodeOperation: nodeOperation)
            return
        }

        // index is not nil because parentNode is not nil
        let index = treeNode.index!
        let item: PropertyListItem

        switch parentNode.item {
        case var .ArrayItem(array):
            array.replaceElementAtIndex(index, withElement: newValue)
            item = .ArrayItem(array)
        case var .DictionaryItem(dictionary):
            dictionary.setValue(newValue, atIndex: index)
            item = .DictionaryItem(dictionary)
        default:
            item = newValue
        }

        let nodeOperation: TreeNodeOperation? = needsChildRegeneration ? .RegenerateChildrenForChildAtIndex(index) : nil
        self.setItem(item, ofTreeNodeAtIndexPath: parentNode.indexPath, nodeOperation: nodeOperation)
    }


    private func insertItem(item: PropertyListItem, atIndex index: Int, inTreeNode treeNode: PropertyListTreeNode) {
        let newItem: PropertyListItem

        switch treeNode.item {
        case var .ArrayItem(array):
            array.insertElement(item, atIndex: index)
            newItem = .ArrayItem(array)
        case var .DictionaryItem(dictionary):
            dictionary.insertKey(dictionary.unusedKey(), value: item, atIndex: index)
            newItem = .DictionaryItem(dictionary)
        default:
            assert(false, "Attempt to insert child at index \(index) in scalar tree node \(treeNode)")
            return
        }

        self.setItem(newItem, ofTreeNodeAtIndexPath: treeNode.indexPath, nodeOperation: .InsertChildAtIndex(index))
    }


    private func removeItemAtIndex(index: Int, inTreeNode treeNode: PropertyListTreeNode) {
        let newItem: PropertyListItem

        switch treeNode.item {
        case var .ArrayItem(array):
            array.removeElementAtIndex(index)
            newItem = .ArrayItem(array)
        case var .DictionaryItem(dictionary):
            dictionary.removeElementAtIndex(index)
            newItem = .DictionaryItem(dictionary)
        default:
            assert(false, "Attempt to remove child at index \(index) in scalar tree node \(treeNode)")
            return
        }

        self.setItem(newItem, ofTreeNodeAtIndexPath: treeNode.indexPath, nodeOperation: .RemoveChildAtIndex(index))
    }


    private func setItem(newItem: PropertyListItem, ofTreeNodeAtIndexPath indexPath: NSIndexPath, nodeOperation: TreeNodeOperation? = nil) {
        let treeNode = self.tree.nodeAtIndexPath(indexPath)
        let oldItem = treeNode.item

        self.undoManager!.registerUndoWithHandler { [unowned self] in
            self.setItem(oldItem, ofTreeNodeAtIndexPath: indexPath, nodeOperation: nodeOperation?.inverseOperation)
        }

        treeNode.item = newItem
        nodeOperation?.performOperationOnTreeNode(treeNode)

        self.propertyListOutlineView.reloadItem(treeNode, reloadChildren: true)

        if let nodeOperation = nodeOperation {
            switch nodeOperation {
            case let .InsertChildAtIndex(index):
                self.propertyListOutlineView.expandItem(treeNode.childAtIndex(index))
            case let .RegenerateChildrenForChildAtIndex(index):
                self.propertyListOutlineView.expandItem(treeNode.childAtIndex(index))
            case .RegenerateChildren:
                self.propertyListOutlineView.expandItem(treeNode)
            default:
                break
            }
        }
    }


    private func itemForAdding() -> PropertyListItem {
        return PropertyListItem(propertyListType: .StringType)
    }
}


// MARK: - Generating Unused Dictionary Keys

private extension PropertyListDictionary {
    /// Returns a key that the instance does not contain.
    private func unusedKey() -> String {
        let formatString = NSLocalizedString("PropertyListDocument.KeyForAddingFormat",
                                             comment: "Format string for key generated when adding a dictionary item")

        var key: String
        var counter: Int = 1
        repeat {
            key = NSString.localizedStringWithFormat(formatString, counter++) as String
        } while self.containsKey(key)

        return key
    }
}


// MARK: - PropertyListItem and PropertyListType Extensions

private extension PropertyListItem {
    init(propertyListType: PropertyListType) {
        switch propertyListType {
        case .ArrayType:
            self = .ArrayItem(PropertyListArray())
        case .BooleanType:
            self = .BooleanItem(false)
        case .DataType:
            self = .DataItem(NSData())
        case .DateType:
            self = .DateItem(NSDate())
        case .DictionaryType:
            self = .DictionaryItem(PropertyListDictionary())
        case .NumberType:
            self = .NumberItem(NSNumber(integer: 0))
        case .StringType:
            let string = NSLocalizedString("PropertyListDocument.ItemForAddingStringValue", comment: "Default value when adding a new item")
            self = .StringItem(string)
        }
    }


    func propertyListItemByConvertingToType(type: PropertyListType) -> PropertyListItem {
        if self.propertyListType == type {
            return self
        }

        let defaultItem = PropertyListItem(propertyListType: type)

        switch self {
        case let .ArrayItem(array):
            if type == .DictionaryType {
                var dictionary = PropertyListDictionary()

                for element in array.elements {
                    dictionary.addKey(dictionary.unusedKey(), value: element)
                }

                return .DictionaryItem(dictionary)
            }

            return defaultItem
        case let .BooleanItem(boolean):
            switch type {
            case .NumberType:
                return .NumberItem(boolean.boolValue ? 1 : 0)
            case .StringType:
                return .StringItem(self.description)
            default:
                return defaultItem
            }
        case let .DateItem(date):
            return type == .NumberType ? .NumberItem(date.timeIntervalSince1970) : defaultItem
        case let .DictionaryItem(dictionary):
            if type == .ArrayType {
                var array = PropertyListArray()

                for element in dictionary.elements {
                    array.addElement(element.value)
                }

                return .ArrayItem(array)
            }

            return defaultItem
        case let .NumberItem(number):
            switch type {
            case .BooleanType:
                return .BooleanItem(number.boolValue)
            case .DateType:
                return .DateItem(NSDate(timeIntervalSince1970: number.doubleValue))
            case .StringType:
                return .StringItem(number.description)
            default:
                return defaultItem
            }
        case let .StringItem(string):
            switch type {
            case .BooleanType:
                return .BooleanItem(string.caseInsensitiveCompare("YES") == .OrderedSame || string.caseInsensitiveCompare("true") == .OrderedSame)
            case .DataType:
                if let data = PropertyListDataFormatter().dataFromString(string as String) {
                    return .DataItem(data)
                }

                return defaultItem
            case .DateType:
                if let date = LenientDateFormatter().dateFromString(string as String) {
                    return .DateItem(date)
                }

                return defaultItem
            case .NumberType:
                if let number = NSNumberFormatter.propertyListNumberFormatter().numberFromString(string as String) {
                    return .NumberItem(number)
                }

                return defaultItem
            default:
                return defaultItem
            }
        default:
            return defaultItem
        }
    }
}


private extension PropertyListType {
    init?(typePopUpMenuItemIndex index: Int) {
        switch index {
        case 0:
            self = .ArrayType
        case 1:
            self = .DictionaryType
        case 3:
            self = .BooleanType
        case 4:
            self = .DataType
        case 5:
            self = .DateType
        case 6:
            self = .NumberType
        case 7:
            self = .StringType
        default:
            return nil
        }
    }


    var typePopUpMenuItemIndex: Int {
        switch self {
        case .ArrayType:
            return 0
        case .DictionaryType:
            return 1
        case .BooleanType:
            return 3
        case .DataType:
            return 4
        case .DateType:
            return 5
        case .NumberType:
            return 6
        case .StringType:
            return 7
        }
    }
}


// MARK: - Value Constraints

/// `PropertyListValueConstraints` represent constraints for valid values on property list items.
/// A value constraint can take one of two forms: a formatter that should be used to convert 
/// to and from a string representation of the value; and an array of valid values that represent
/// all the values the item can have.
private enum PropertyListValueConstraint {
    /// Represents a formatter value constraint.
    case Formatter(NSFormatter)

    /// Represents an array of valid values.
    case ValueArray([PropertyListValidValue])
}


/// `PropertyListValidValues` represent the valid values that a property list item can have.
private struct PropertyListValidValue {
    /// An object representation of the value.
    let value: PropertyListItemConvertible

    /// A localized, user-presentable description of the value.
    let localizedDescription: String
}



private extension PropertyListItem {
    /// Returns an value constraint for the property list item type or `nil` if there are
    // no constraints for the item.
    var valueConstraint: PropertyListValueConstraint? {
        switch self {
        case .BooleanItem:
            let falseTitle = NSLocalizedString("PropertyListValue.Boolean.FalseTitle", comment: "Title for Boolean false value")
            let falseValidValue = PropertyListValidValue(value: NSNumber(bool: false), localizedDescription: falseTitle)
            let trueTitle = NSLocalizedString("PropertyListValue.Boolean.TrueTitle", comment: "Title for Boolean true value")
            let trueValidValue = PropertyListValidValue(value: NSNumber(bool: true), localizedDescription: trueTitle)
            return .ValueArray([falseValidValue, trueValidValue])
        case .DataItem:
            return .Formatter(PropertyListDataFormatter())
        case .DateItem:
            struct SharedFormatter {
                static let dateFormatter = LenientDateFormatter()
            }

            return .Formatter(SharedFormatter.dateFormatter)
        case .NumberItem:
            return .Formatter(NSNumberFormatter.propertyListNumberFormatter())
        default:
            return nil
        }
    }
}


// MARK: - Tree Node Operations

/// The `TreeNodeOperation` enum enumerates the different operations that can be taken on a
/// tree node. Because all operations on a property list item ultimately boils down to
/// replacing an item with a new one, we need some way to discern what corresponding node
/// operation needs to take place. That’s what `TreeNodeOperations` are for.
private enum TreeNodeOperation {
    /// Indicates that a child node should be inserted at the specified index.
    case InsertChildAtIndex(Int)

    /// Indicates that the child node at the specified index should be removed.
    case RemoveChildAtIndex(Int)

    /// Indicates that the child node at the specified index should have its children
    /// regenerated.
    case RegenerateChildrenForChildAtIndex(Int)

    /// Indicates that the node should regenerate its children.
    case RegenerateChildren


    /// Returns the inverse of the specified operation. This is useful when undoing an
    /// operation.
    var inverseOperation: TreeNodeOperation {
        switch self {
        case let .InsertChildAtIndex(index):
            return .RemoveChildAtIndex(index)
        case let .RemoveChildAtIndex(index):
            return .InsertChildAtIndex(index)
        case .RegenerateChildrenForChildAtIndex, .RegenerateChildren:
            return self
        }
    }


    /// Performs the instance’s operation on the specified tree node.
    /// - parameter treeNode: The tree node on which to perform the operation.
    func performOperationOnTreeNode(treeNode: PropertyListTreeNode) {
        switch self {
        case let .InsertChildAtIndex(index):
            treeNode.insertChildAtIndex(index)
        case let .RemoveChildAtIndex(index):
            treeNode.removeChildAtIndex(index)
        case let .RegenerateChildrenForChildAtIndex(index):
            treeNode.childAtIndex(index).regenerateChildren()
        case RegenerateChildren:
            treeNode.regenerateChildren()
        }
    }
}
