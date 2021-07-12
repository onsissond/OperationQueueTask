import UIKit
import PlaygroundSupport

/*
 Условие:
 Дана асинхронная функция func upload(item: Item, completion: @escaping (Bool)->Void), которая загружает структуру Item на сервер по сети и получает в колбэке признак успешности операции.
 Задача:
 Напишите код, загружающий на сервер массив структур [Item] без ошибок и возвращающий признак успешности загрузки всего массива. Использование высокоуровневых библиотек типа RxSwift, Combine и им подобных не разрешается. Архитектура на ваше усмотрение.
 */


typealias Completion = (Bool) -> Void
typealias Upload<Item> = (Item, @escaping Completion) -> Void

class ItemService<Item> {
    private lazy var _queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        return queue
    }()

    private let _uploadItem: Upload<Item>
    private let _retryAttempts: UInt

    init(
        uploadItem: @escaping Upload<Item>,
        retryAttempts: UInt = 1,
        maxConcurrentOperationCount: Int = 1
    ) {
        _uploadItem = uploadItem
        _retryAttempts = retryAttempts
        _queue.maxConcurrentOperationCount = maxConcurrentOperationCount
    }

    func upload(
        item: Item,
        completionQueue: DispatchQueue = .main,
        completion: @escaping (Bool) -> Void
    ) {
        upload(
            items: [item],
            completionQueue: completionQueue,
            completion: completion
        )
    }

    func upload(
        items: [Item],
        completionQueue: DispatchQueue = .main,
        completion: @escaping (Bool) -> Void
    ) {
        let uploadOperations: [ItemUploadOperation<Item>] = items.map {
            ItemUploadOperation(
                item: $0,
                attempts: _retryAttempts,
                upload: _uploadItem
            )
        }
        let complitionOperation = BlockOperation {
            let results = uploadOperations.map(\.result)
            completionQueue.async {
                completion(results.allSatisfy { $0 == true })
            }
        }
        uploadOperations.forEach { complitionOperation.addDependency($0) }
        _queue.addOperations(
            uploadOperations + [complitionOperation],
            waitUntilFinished: false
        )
    }

    func cancel() {
        _queue.cancelAllOperations()
    }
}

open class AsyncOperation: Operation {
    var state: State = .ready {
        willSet {
            willChangeValue(forKey: state.keyPath)
            willChangeValue(forKey: newValue.keyPath)
        }
        didSet {
            didChangeValue(forKey: oldValue.keyPath)
            didChangeValue(forKey: state.keyPath)
        }
    }

    public override var isReady: Bool {
        super.isReady && state == .ready
    }

    public override var isExecuting: Bool {
        state == .executing
    }

    public override var isFinished: Bool {
        state == .finished
    }

    public override var isAsynchronous: Bool { true }

    public override func start() {
        if isCancelled {
            state = .finished
            return
        }
        state = .executing
        main()
    }

    public override func cancel() {
        super.cancel()
        state = .finished
    }
}

extension AsyncOperation {
    enum State: String {
        case ready
        case executing
        case finished

        fileprivate var keyPath: String {
            "is" + rawValue.capitalized
        }
    }
}

class ItemUploadOperation<Item>: AsyncOperation {
    typealias Completion = (Bool) -> Void
    typealias Upload = (Item, @escaping Completion) -> Void
    private let _upload: Upload
    private let _item: Item
    private var _attempts: UInt
    var result: Bool?

    init(item: Item, attempts: UInt = 1, upload: @escaping Upload) {
        _item = item
        _upload = upload
        _attempts = attempts
    }

    override func main() {
        _attempts -= 1
        _upload(_item) { [weak self] result in
            guard let self = self else { return }
            if self.isCancelled { return }
            guard self._attempts > 0 && !result else {
                self.result = result
                self.state = .finished
                return
            }
            self.main()
        }
    }
}


PlaygroundPage.current.needsIndefiniteExecution = true

var iterator = [false, true, false].makeIterator()
let service = ItemService<String>(uploadItem: { item, completion in
    let uuid = UUID()
    print("Start operation \(uuid.uuidString) with argument \(item)")
    sleep(5)
    print("Finish operation \(uuid.uuidString) with argument \(item)")
    completion(iterator.next()!)
}, retryAttempts: 2, maxConcurrentOperationCount: 2)

service.upload(items: ["My little task 1", "My favorite task 2"]) { result in
    print("Completion operation with result \(result)")
}
print("After call")
service.cancel()
