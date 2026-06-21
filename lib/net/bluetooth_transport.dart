import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'transport.dart';

/// 基于 flutter_blue_plus 的蓝牙传输（中心角色）。
///
/// ⚠️ 已知限制：flutter_blue_plus 仅支持 BLE **中心角色**（扫描+连接外设），
/// 不支持**外设角色**（广播自定义 GATT 服务）。因此两端 App 直接 P2P 互联，
/// 需要其中一端能广播我们的服务 UUID——这需要额外的原生外设实现
///（如 iOS `CBPeripheralManager` / Android `BluetoothGattServer`）或改用经典蓝牙
/// RFCOMM（`BluetoothSocket`）。本类实现了中心侧的扫描/连接/GATT 读写+通知与
/// 消息分帧，可作为联机传输的基础；**完整 P2P 需真机与外设侧方案后验证**。
///
/// 消息分帧：4 字节大端长度前缀 + JSON utf8 负载，支持超过 MTU 的消息。
class BluetoothTransport implements Transport {
  @override
  final String localId;
  final Guid serviceUuid;
  final Guid writeCharUuid; // 我方写入对端
  final Guid notifyCharUuid; // 对端通知我方

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  final StreamController<TransportMessage> _controller =
      StreamController<TransportMessage>.broadcast();

  BluetoothTransport({
    required this.localId,
    required this.serviceUuid,
    required this.writeCharUuid,
    required this.notifyCharUuid,
  });

  @override
  Stream<TransportMessage> get messages => _controller.stream;

  @override
  Future<void> start() async {
    // 等待蓝牙适配器开启；实际扫描/连接由 [connectTo] 触发。
    await FlutterBluePlus.adapterState
        .firstWhere((s) => s == BluetoothAdapterState.on);
  }

  /// 扫描并连接到广播本服务 UUID 的第一个外设，发现特征值并订阅通知。
  Future<void> connectTo({Duration timeout = const Duration(seconds: 10)}) async {
    await FlutterBluePlus.startScan(withServices: [serviceUuid], timeout: timeout);
    final result = await FlutterBluePlus.scanResults
        .firstWhere((r) => r.isNotEmpty)
        .timeout(timeout);
    await FlutterBluePlus.stopScan();

    _device = result.first.device;
    // flutter_blue_plus 2.x：connect 需声明 License（个人/非营利用 nonprofit）。
    await _device!.connect(license: License.nonprofit, mtu: 512);

    final services = await _device!.discoverServices();
    final service = services.firstWhere((s) => s.uuid == serviceUuid);
    _writeChar = service.characteristics.firstWhere((c) => c.uuid == writeCharUuid);
    _notifyChar = service.characteristics.firstWhere((c) => c.uuid == notifyCharUuid);
    await _notifyChar!.setNotifyValue(true);

    final framer = _LengthPrefixFramer();
    _notifyChar!.lastValueStream.listen((bytes) {
      for (final msg in framer.push(bytes)) {
        _controller.add(TransportMessage(_device!.remoteId.str, msg));
      }
    });
  }

  @override
  Future<void> sendTo(String peerId, List<int> bytes) async {
    final char = _writeChar;
    if (char == null) throw StateError('Not connected');
    final framed = _LengthPrefixFramer.frame(bytes);
    // 分片写入以适应 MTU（默认 20 字节负载）。
    final mtu = 20;
    for (var i = 0; i < framed.length; i += mtu) {
      final end = (i + mtu > framed.length) ? framed.length : i + mtu;
      await char.write(framed.sublist(i, end), withoutResponse: false);
    }
  }

  @override
  Future<void> broadcast(List<int> bytes) async {
    // 蓝牙为点对点连接；只有一个对端时等同 sendTo。
    await sendTo('', bytes);
  }

  @override
  Future<void> close() async {
    await _device?.disconnect();
    await _controller.close();
  }
}

/// 4 字节大端长度前缀分帧器：把可能分片到达的 notify 字节流重组为完整消息。
class _LengthPrefixFramer {
  final BytesBuilder _buf = BytesBuilder();

  Iterable<List<int>> push(List<int> chunk) sync* {
    _buf.add(chunk);
    var data = _buf.toBytes();
    while (data.length >= 4) {
      final len = (data[0] << 24) | (data[1] << 16) | (data[2] << 8) | data[3];
      if (data.length < 4 + len) break;
      final payload = data.sublist(4, 4 + len);
      yield payload;
      data = data.sublist(4 + len);
    }
    _buf.clear();
    _buf.add(data);
  }

  static List<int> frame(List<int> payload) {
    final len = payload.length;
    final out = ByteData(4 + len);
    out.setUint32(0, len);
    final bytes = out.buffer.asUint8List();
    bytes.setRange(4, 4 + len, payload);
    return bytes;
  }
}
