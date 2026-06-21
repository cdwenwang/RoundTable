import 'dart:async';

import 'transport.dart';

/// 进程内传输 Hub：把多个 [MockTransport] 节点连成一张虚拟局域网。
///
/// 用于桌面/Web 调试联机逻辑（含心智扑克协议），无需真机即可跑通多方对局。
class MockTransportHub {
  final Map<String, MockTransport> _nodes = {};

  MockTransport create(String id) {
    if (_nodes.containsKey(id)) {
      throw StateError('Node $id already exists');
    }
    final t = MockTransport._(id, this);
    _nodes[id] = t;
    return t;
  }

  void _deliver(String fromId, String? toId, List<int> bytes) {
    for (final entry in _nodes.entries) {
      if (entry.key == fromId) continue;
      if (toId == null || entry.key == toId) {
        entry.value._controller.add(TransportMessage(fromId, bytes));
      }
    }
  }

  List<String> get nodeIds => _nodes.keys.toList();
}

class MockTransport implements Transport {
  final String _id;
  final MockTransportHub _hub;
  // sync: true 使监听器在 add 时同步触发，保证协议消息的收发顺序确定（联机模拟用）。
  final StreamController<TransportMessage> _controller =
      StreamController<TransportMessage>.broadcast(sync: true);

  MockTransport._(this._id, this._hub);

  @override
  String get localId => _id;

  @override
  Stream<TransportMessage> get messages => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> sendTo(String peerId, List<int> bytes) async {
    _hub._deliver(_id, peerId, bytes);
  }

  @override
  Future<void> broadcast(List<int> bytes) async {
    _hub._deliver(_id, null, bytes);
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
