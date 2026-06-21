import 'dart:async';

/// 传输层抽象：面向「消息」的端到端通信，不耦合蓝牙细节。
///
/// 心智扑克协议与联机会话只依赖此接口；桌面用 [MockTransport] 模拟多设备，
/// 真机用 [BluetoothTransport]（flutter_blue_plus）实现。
abstract class Transport {
  /// 本机节点 id。
  String get localId;

  /// 收到的消息流（`fromId` 为发送方）。
  Stream<TransportMessage> get messages;

  /// 启动传输（扫描/广播/连接等）。
  Future<void> start();

  /// 点对点发送。
  Future<void> sendTo(String peerId, List<int> bytes);

  /// 广播给所有已连接节点。
  Future<void> broadcast(List<int> bytes);

  Future<void> close();
}

class TransportMessage {
  final String fromId;
  final List<int> bytes;

  const TransportMessage(this.fromId, this.bytes);
}
