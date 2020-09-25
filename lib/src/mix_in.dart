import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/src/widgets/async.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

mixin GetItMixin on StatelessWidget {
  final _MixinState _state = _MixinState();
  @override
  StatelessElement createElement() => _StatelessMixInElement(this, _state);

  /// all the following functions can be called inside the build function but also
  /// in e.g. in `initState` of a `StatefulWidget`.
  /// The mixin takes care that everything is correctly disposed.

  /// retrieves or creates an instance of a registered type [T] depending on the registration
  /// function used for this type or based on a name.
  /// for factories you can pass up to 2 parameters [param1,param2] they have to match the types
  /// given at registration with [registerFactoryParam()]
  T get<T>({String instanceName, dynamic param1, dynamic param2}) =>
      GetIt.I<T>(instanceName: instanceName, param1: param1, param2: param2);

  /// like [get] but for async registrations
  Future<T> getAsync<T>(
          {String instanceName, dynamic param1, dynamic param2}) =>
      GetIt.I.getAsync<T>(
          instanceName: instanceName, param1: param1, param2: param2);

  /// like [get] but with an additional [select] function to return a member of [T]
  R getX<T, R>(R Function(T) accessor, {String instanceName}) {
    assert(accessor != null);
    return accessor(GetIt.I<T>(instanceName: instanceName));
  }

  /// like [get] but it also registers a listener to [T] and
  /// triggers a rebuild every time [T] signals a change
  T watch<T extends Listenable>({String instanceName}) =>
      _state.watch<T>(instanceName: instanceName);

  /// like [get] but it also registers a listener to the result of [select] and
  /// triggers a rebuild every time signals [R] a change
  /// useful if the `Listenable` [R] is a member of your business object [T]
  R watchX<T, R extends Listenable>(
    R Function(T) select, {
    String instanceName,
  }) =>
      _state.watchX<T, R>(select, instanceName: instanceName);

  /// like watch but it only triggers a rebuild when the value that the function
  /// [only] returns changes. With that you can react to changes of single members
  /// of [T]
  R watchOnly<T extends Listenable, R>(
    R Function(T) only, {
    String instanceName,
  }) =>
      _state.watchOnly<T, R>(only, instanceName: instanceName);

  /// a combination of [watchX] and [watchOnly]
  R watchXOnly<T, Q extends Listenable, R>(
    Q Function(T) select,
    R Function(Q) only, {
    String instanceName,
  }) =>
      _state.watchXOnly<T, Q, R>(select, only, instanceName: instanceName);

  /// subscribes to the `Stream` returned by [select] and returns
  /// an `AsyncSnapshot` with the latest received data from the `Stream`
  /// Whenever new data is received it triggers a rebuild.
  /// When you call [watchStream] a second time on the same `Stream` it will
  /// return the last received data but not subscribe another time.
  /// To be able to use [watchStream] inside a `build` function we have to pass
  /// [initialValue] so that it can return something before it has received the first data
  /// if [select] returns a different Stream than on the last call, [watchStream]
  /// will cancel the previous subscription and subscribe to the new stream.
  /// [preserveState] determines then if the new initial value should be the last
  /// value of the previous stream or again [initialValue]
  AsyncSnapshot<R> watchStream<T, R>(
    Stream<R> Function(T) select,
    R initialValue, {
    String instanceName,
    bool preserveState = true,
  }) =>
      _state.watchStream<T, R>(select, initialValue,
          instanceName: instanceName, preserveState: preserveState);

  /// awaits the ` Future` returned by [select] and triggers a rebuild as soon
  /// as the `Future` completes. After that it returns
  /// an `AsyncSnapshot` with the received data from the `Future`
  /// When you call [watchFuture] a second time on the same `Future` it will
  /// return the last received data but not observe the Future a another time.
  /// To be able to use [watchStream] inside a `build` function
  /// we have to pass [initialValue] so that it can return something before
  /// the `Future` has completed
  /// if [select] returns a different `Future` than on the last call, [watchFuture]
  /// will ignore the completion of the previous Future and observe the completion
  /// of the new Future.
  /// [preserveState] determines then if the new initial value should be the last
  /// value of the previous stream or again [initialValue]
  AsyncSnapshot<R> watchFuture<T, R>(
    Future<R> Function(T) select,
    R initialValue, {
    String instanceName,
    bool preserveState = true,
  }) =>
      _state.watchFuture<T, R>(select, initialValue,
          instanceName: instanceName, preserveState: preserveState);

  /// Pushes a new GetIt-Scope. After pushing it executes [init] where you can register
  /// objects that should only exist as long as this scope exists.
  /// Can be called inside the `build` method method of a `StatelessWidget`.
  /// It ensures that it's only called once in the lifetime of a widget.
  /// When the widget is destroyed the scope too gets destroyed after [dispose]
  /// is executed. If you use this function and you have registered your objects with
  /// an async disposal function, that functions won't be awaited.
  /// I would recommend doing pushing and popping from your business layer but sometimes
  /// this might come in handy
  void pushScope({void Function(GetIt getIt) init, void Function() dispose}) =>
      _state.pushScope(init: init, dispose: dispose);
}

class _StatelessMixInElement extends StatelessElement with _GetItElement {
  _StatelessMixInElement(Widget widget, _MixinState state) : super(widget) {
    _state = state;
  }
}

mixin _GetItElement on ComponentElement {
  _MixinState _state;

  @override
  void mount(Element parent, newSlot) {
    _state.init(this);
    super.mount(parent, newSlot);
  }

  @override
  Widget build() {
    _state.resetCurrentWatch();
    return super.build();
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    _state.clearRegistratons();
  }

  @override
  void reassemble() {
    super.reassemble();
  }

  @override
  void unmount() {
    _state.dispose();
    super.unmount();
  }
}

class _WatchEntry<T> extends LinkedListEntry<_WatchEntry<T>> {
  Listenable currentListenable;
  Function notificationHandler;
  StreamSubscription subscription;
  Stream currentStream;
  Future currentFuture;
  void Function(_WatchEntry entry) _dispose;
  T lastValue;
  _WatchEntry(
      {this.notificationHandler,
      this.subscription,
      this.currentFuture,
      void Function(_WatchEntry entry) dispose,
      this.lastValue,
      this.currentStream,
      this.currentListenable})
      : _dispose = dispose;
  void dispose() {
    _dispose(this);
  }
}

class _MixinState {
  Element _element;

  LinkedList<_WatchEntry> watchList = LinkedList<_WatchEntry>();
  _WatchEntry currentWatch;

  void init(Element element) {
    _element = element;
  }

  void resetCurrentWatch() {
    currentWatch = watchList.isNotEmpty ? watchList.first : null;
  }

  _WatchEntry<T> _getWatch<T>() {
    if (currentWatch != null) {
      final result = currentWatch;
      currentWatch = currentWatch.next;
      return result as _WatchEntry<T>;
    }
    return null;
  }

  void _appendWatch(_WatchEntry entry) {
    watchList.add(entry);
    currentWatch = null;
  }

  T watch<T extends Listenable>({String instanceName}) {
    final listenable = GetIt.I<T>(instanceName: instanceName);
    final watch = _getWatch<T>();

    if (watch == null) {
      final handler = () => _element.markNeedsBuild();
      _appendWatch(_WatchEntry<T>(
        currentListenable: listenable,
        lastValue: listenable,
        notificationHandler: handler,
        dispose: (x) => listenable.removeListener(x.notificationHandler),
      ));
      listenable.addListener(handler);
    }
    return listenable;
  }

  R watchX<T, R extends Listenable>(
    R Function(T) select, {
    String instanceName,
  }) {
    assert(select != null, 'select can\'t be null if you use watchX');
    final parentObject = GetIt.I<T>(instanceName: instanceName);
    final listenable = select(parentObject);
    assert(listenable == null, 'select returned null in watchX');

    _WatchEntry<R> watch = _getWatch();

    if (watch != null) {
      if (select(parentObject) == watch.currentListenable) {
        return watch.lastValue;
      } else {
        /// select returned a different value than the last time
        /// so we have to unregister out handler and subscribe anew
        watch.dispose();
      }
    } else {
      _appendWatch(_WatchEntry<R>(
        dispose: (x) => listenable.removeListener(
          x.notificationHandler,
        ),
      ));
    }

    final handler = () => _element.markNeedsBuild();
    watch.notificationHandler = handler;
    watch.currentListenable = listenable;

    listenable.addListener(handler);
    return listenable;
  }

  R watchOnly<T extends Listenable, R>(
    R Function(T) only, {
    String instanceName,
  }) {
    assert(only != null, 'only can\'t be null if you use watchOnly');
    final parentObject = GetIt.I<T>(instanceName: instanceName);

    _WatchEntry<R> alreadyRegistered = _getWatch();

    if (alreadyRegistered == null) {
      final watch = _WatchEntry<R>(
          currentListenable: parentObject,
          lastValue: only(parentObject),
          dispose: (x) => parentObject.removeListener(x.notificationHandler));

      final handler = () {
        final newValue = only(parentObject);
        if (watch.lastValue != newValue) {
          _element.markNeedsBuild();
          watch.lastValue = newValue;
        }
      };
      watch.notificationHandler = handler;
      _appendWatch(watch);

      parentObject.addListener(handler);
    }
    return only(parentObject);
  }

  R watchXOnly<T, Q extends Listenable, R>(
    Q Function(T) select,
    R Function(Q) only, {
    String instanceName,
  }) {
    assert(only != null, 'only can\'t be null if you use watchXOnly');
    assert(select != null, 'select can\'t be null if you use watchXOnly');
    final parentObject = GetIt.I<T>(instanceName: instanceName);
    final Q listenable = select(parentObject);
    assert(listenable != null, 'watchXOnly: select must return a Listenable');

    _WatchEntry<R> watch = _getWatch();

    if (watch != null) {
      if (listenable == watch.currentListenable) {
        return watch.lastValue;
      } else {
        /// select returned a different value than the last time
        /// so we have to unregister out handler and subscribe anew
        watch.dispose();
      }
    } else {
      watch = _WatchEntry<R>(
          lastValue: only(listenable),
          dispose: (x) => listenable.removeListener(x.notificationHandler));
      _appendWatch(watch);
    }

    final handler = () {
      final newValue = only(listenable);
      if (watch.lastValue != newValue) {
        _element.markNeedsBuild();
        watch.lastValue = newValue;
      }
    };

    watch.currentListenable = listenable;
    watch.notificationHandler = handler;

    listenable.addListener(handler);
    return only(listenable);
  }

  AsyncSnapshot<R> watchStream<T, R>(
    Stream<R> Function(T) select,
    R initialValue, {
    String instanceName,
    bool preserveState = true,
  }) {
    assert(select != null, 'select can\'t be null if you use watchStream');
    final parentObject = GetIt.I<T>(instanceName: instanceName);
    final stream = select(parentObject);
    assert(stream != null, 'select returned null in watchX');

    _WatchEntry<AsyncSnapshot<R>> watch = _getWatch();

    if (watch != null) {
      if (stream == watch.currentStream) {
        ///  still the same stream so we can directly return lastvalue
        return watch.lastValue;
      } else {
        /// select returned a different value than the last time
        /// so we have to unregister out handler and subscribe anew
        watch.dispose();
        initialValue =
            preserveState ? watch.lastValue ?? initialValue : initialValue;
      }
    } else {
      watch = _WatchEntry(dispose: (x) => x.subscription.cancel());
      _appendWatch(watch);
    }

    // ignore: cancel_subscriptions
    final subscription = stream.listen(
      (x) {
        watch.lastValue = AsyncSnapshot.withData(ConnectionState.active, x);
        _element.markNeedsBuild();
      },
      onError: (error) {
        watch.lastValue =
            AsyncSnapshot.withError(ConnectionState.active, error);
        _element.markNeedsBuild();
      },
    );
    watch.subscription = subscription;
    watch.currentStream = stream;
    watch.lastValue =
        AsyncSnapshot<R>.withData(ConnectionState.waiting, initialValue);

    return watch.lastValue;
  }

  AsyncSnapshot<R> watchFuture<T, R>(
      Future<R> Function(T) select, R initialValue,
      {String instanceName, bool preserveState}) {
    assert(select != null, 'select can\'t be null if you use watchStream');
    final parentObject = GetIt.I<T>(instanceName: instanceName);
    final future = select(parentObject);
    assert(future != null, 'select returned null in watchX');

    _WatchEntry<AsyncSnapshot<R>> watch = _getWatch();

    if (watch != null) {
      if (future == watch.currentFuture) {
        ///  still the same future so we can directly return lastvalue
        return watch.lastValue;
      } else {
        /// select returned a different value than the last time
        /// so we have to unregister out handler and subscribe anew
        watch.dispose();
        initialValue =
            preserveState ? watch.lastValue ?? initialValue : initialValue;
      }
    } else {
      watch = _WatchEntry(dispose: (x) => x.currentFuture = null);
      _appendWatch(watch);
    }

    watch.currentFuture = future.then(
      (x) {
        if (watch.currentFuture != null) {
          // only update if Future is still valid
          watch.lastValue = AsyncSnapshot.withData(ConnectionState.active, x);
          _element.markNeedsBuild();
        }
      },
      onError: (error) {
        if (watch.currentFuture != null) {
          watch.lastValue =
              AsyncSnapshot.withError(ConnectionState.active, error);
          _element.markNeedsBuild();
        }
      },
    );
    watch.lastValue =
        AsyncSnapshot<R>.withData(ConnectionState.waiting, initialValue);

    return watch.lastValue;
  }

  bool _scopeWasPushed = false;

  void pushScope({void Function(GetIt getIt) init, void Function() dispose}) {
    if (!_scopeWasPushed) {
      GetIt.I.pushNewScope(dispose: dispose);
      init(GetIt.I);
    }
  }

  void clearRegistratons() {
    watchList.forEach((x) => x.dispose());
    watchList.clear();
    currentWatch = null;
  }

  void dispose() {
    clearRegistratons();
    if (_scopeWasPushed) {
      GetIt.I.popScope();
    }
    _element = null; // making sure the Garbage collector can do its job
  }
}
