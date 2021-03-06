/*
 * Copyright (c) 2019, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation
import Promises
import ReactiveSwift

public typealias Reducer<Value, Action, Environment> =
    (inout Value, Action, Environment) -> [Effect<Action>]

public func combine<Value, Action, Environment>(
    _ reducers: Reducer<Value, Action, Environment>...
) -> Reducer<Value, Action, Environment> {
    return { value, action, environment in
        let effects = reducers.flatMap { $0(&value, action, environment) }
        return effects
    }
}

public func pullback<LocalValue, GlobalValue, LocalAction, GlobalAction, LocalEnv, GlobalEnv>(
    _ localReducer: @escaping Reducer<LocalValue, LocalAction, LocalEnv>,
    value valuePath: WritableKeyPath<GlobalValue, LocalValue>,
    action actionPath: WritableKeyPath<GlobalAction, LocalAction?>,
    environment toLocalEnvironment: @escaping (GlobalEnv) -> (LocalEnv)
) -> Reducer<GlobalValue, GlobalAction, GlobalEnv> {
    return { globalValue, globalAction, globalEnv in

        // Converts GlobalAction into LocalAction accepted by `localReducer`.
        guard let localAction = globalAction[keyPath: actionPath] else { return [] }

        let effects = localReducer(&globalValue[keyPath: valuePath], localAction,
                                   toLocalEnvironment(globalEnv))

        // Pulls local action into global action.
        let pulledLocalEffects = effects.map { localEffect in
            localEffect.map { localAction -> GlobalAction in
                var globalAction = globalAction
                globalAction[keyPath: actionPath] = localAction
                return globalAction
            }
        }

        return pulledLocalEffects
    }
}

/// An event-driven state machine that runs it's effects on the main thread.
/// Can be observed from any other thread, however, events can only be sent to it on the main-thread.
public final class Store<Value: Equatable, Action> {
    public typealias OutputType = Value
    public typealias OutputErrorType = Never
    public typealias StoreReducer = Reducer<Value, Action, ()>

    @State public private(set) var value: Value

    private let scheduler: UIScheduler
    private var reducer: StoreReducer!
    private var disposable: Disposable? = .none
    private var effectDisposables = CompositeDisposable()
    private let feedbackLogger: FeedbackLogger
    
    /// Count of effects that have not completed.
    public private(set) var outstandingEffectCount = 0
    
    public init<Environment>(
        initialValue: Value,
        reducer: @escaping Reducer<Value, Action, Environment>,
        feedbackLogger: FeedbackLogger,
        environment makeEnvironment: (Store<Value, Action>) -> Environment
    ) {
        self.value = initialValue
        self.scheduler = .init()
        self.feedbackLogger = feedbackLogger
        
        let environment = makeEnvironment(self)
        self.reducer = { value, action, _ in
            reducer(&value, action, environment)
        }
    }
    
    private init(scheduler: UIScheduler, feedbackLogger: FeedbackLogger,
                 initialValue: Value, reducer: @escaping StoreReducer) {
        self.reducer = reducer
        self.value = initialValue
        self.scheduler = scheduler
        self.feedbackLogger = feedbackLogger
    }
    
    deinit {
        effectDisposables.dispose()
    }
     
    /// Sends action to the store.
    public func send(_ action: Action) {
        self.scheduler.schedule { [unowned self] in
            // Executes the reducer and collects the effects
            let effects = self.reducer!(&self.value, action, ())
            
            self.outstandingEffectCount += effects.count

            effects.forEach { effect in
                var disposable: Disposable?
                disposable = effect.observe(on: self.scheduler)
                    .sink(
                        receiveCompletion: {
                            disposable?.dispose()
                            self.outstandingEffectCount -= 1
                        },
                        receiveValues: { [unowned self] internalAction in
                            self.send(internalAction)
                        },
                        feedbackLogger: self.feedbackLogger
                    )
                
                self.effectDisposables.add(disposable)
            }
        }
    }

    /// Creates a  projection of the store value and action types.
    /// - Parameter value: A function that takes current store Value type and maps it to LocalValue.
    public func projection<LocalValue, LocalAction>(
        value toLocalValue: @escaping (Value) -> LocalValue,
        action toGlobalAction: @escaping (LocalAction) -> Action
    ) -> Store<LocalValue, LocalAction> {
        
        let localStore = Store<LocalValue, LocalAction>(
            scheduler: self.scheduler,
            feedbackLogger: self.feedbackLogger,
            initialValue: toLocalValue(self.value),
            reducer: { localValue, localAction, _ in
                // Local projection sends actions to the global MainStore.
                self.send(toGlobalAction(localAction))
                // Updates local stores value immediately.
                localValue = toLocalValue(self.value)
                return []
        })

        // Subscribes localStore to the value changes of the "global store",
        // due to actions outside the localStore.
        localStore.disposable = self.$value.signalProducer
            .map(toLocalValue)
            .skipRepeats()
            .startWithValues { [weak localStore] newValue in
                localStore?.value = newValue
        }

        return localStore
    }

}
