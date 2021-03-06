import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'dart:typed_data';
import "package:hex/hex.dart";

class NfcError extends Error {
  final String code;
  final String message;
  NfcError({this.code, this.message});

  @override
  String toString() {
    return "NfcError: ${code} :: ${message} ";
  }
}

class NfcEvent<T extends BasicTagTechnology> {
  final T tag;

  NfcEvent(this.tag);
}

typedef void OnNfcEvent(NfcEvent event);

class BasicTagTechnology {
  MethodChannel _channel;
  Map<String, dynamic> _info;

  BasicTagTechnology({MethodChannel channel, Map<String, dynamic> info}) : _channel = channel, _info =info;

  //// Base
  Future connect() async {
    return handle(await _channel.invokeMethod('connect'));
  }

  Future close() async {
    await handle(await _channel.invokeMethod('close'));
  }

  Map<String, dynamic> get extraInfo => _info;
}

Uint8List getRequest(dynamic data) {
  var req;
  if (data is String) {
    req = HEX.decode(data);
  } else if (data is List<int>) {
    if (data is Uint8List) {
      req = data;
    } else {
      req = Uint8List.fromList(data);
    }
  } else {
    throw new NfcError(code: FlutterEasyNfc.PARAM_ERROR);
  }
  return req;
}

class IsoDep extends BasicTagTechnology {
  IsoDep({MethodChannel channel, Map<String, dynamic> info}) : super(channel: channel, info: info);

  //// data : String/Uint8List/List
  Future<Uint8List> transceive(dynamic data) async {
    assert(data != null, "Data must not null");
    var res = await _channel.invokeMethod('transceive', getRequest(data));
    return handle(res);
  }
}

dynamic handle(dynamic res) {
  if (res['code'] != null) {
    throw new NfcError(code: res['code'], message: res['message']);
  }
  return res['data'];
}

class MifareClassic extends BasicTagTechnology {
  MifareClassic({MethodChannel channel, Map<String, dynamic> info}) : super(channel: channel, info: info);

  /// For MifareClassic
  Future<bool> authenticateSectorWithKeyA(int sectorIndex, dynamic key) async {
    return handle(await _channel.invokeMethod("authenticateSectorWithKeyA",
        {'sectorIndex': sectorIndex, 'key': getRequest(key)}));
  }

  Future<bool> authenticateSectorWithKeyB(int sectorIndex, dynamic key) async {
    return handle(await _channel.invokeMethod("authenticateSectorWithKeyB",
        {'sectorIndex': sectorIndex, 'key': getRequest(key)}));
  }

  Future<int> blockCount() async {
    return handle(await _channel.invokeMethod('getBlockCount'));
  }

  Future<int> blockSize() async {
    return handle(await _channel.invokeMethod('mifareBlockSize'));
  }

  Future<int> sectorToBlock(int sectorIndex) async {
    return handle(await _channel.invokeMethod("sectorToBlock", { 'sectorIndex': sectorIndex }));
  }

  Future<Uint8List> readBlock(int block) async {
    return handle(await _channel.invokeMethod("readBlock", {
      'block': block,
    }));
  }

  Future writeBlock(int block, dynamic data) async {
    return handle(await _channel.invokeMethod("writeBlock", {
      'block': block,
      'data': getRequest(data),
    }));
  }

  Future transfer(int block) async {
    return handle(await _channel.invokeMethod("transfer", {
      'block': block,
    }));
  }

  Future restore(int block) async {
    return handle(await _channel.invokeMethod("restore", {
      'block': block,
    }));
  }

  Future increment(int block, int value) async {
    return handle(await _channel
        .invokeMethod("increment", {'block': block, 'value': value}));
  }

  Future decrement(int block, int value) async {
    return handle(await _channel
        .invokeMethod("decrement", {'block': block, 'value': value}));
  }

  Future<bool> setTimeout(int timeout) async {
    return handle(await _channel.invokeMethod("setTimeout", { 'timeout': timeout }));
  }
}

class AppLifecycleStateObserver extends WidgetsBindingObserver {
  MethodChannel _channel;
  AppLifecycleStateObserver(MethodChannel channel) : _channel = channel {
    WidgetsBinding.instance.addObserver(this);
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (FlutterEasyNfc._isStartup) {
      if (state == AppLifecycleState.resumed) {
        _channel.invokeMethod("resume");
      } else if (state == AppLifecycleState.paused) {
        _channel.invokeMethod("pause");
      }
    }
  }
}

class FlutterEasyNfc {
  static const String NOT_AVALIABLE = "1";
  static const String NOT_ENABLED = "2";
  static const String NOT_INITIALIZED = "3";
  static const String IO = "4";
  static const String IN_CORRECT_METHOD = "5";
  static const String PARAM_ERROR = "0";
  static const String TAG_LOST = "6";
  static const String COMMON_ERROR = "9";
  static const String MIFARE_INVALID_BLOC = "7";
  static const String MIFARE_INVALID_SECTOR = "8";

  static const MethodChannel _channel = const MethodChannel('flutter_easy_nfc');

  static OnNfcEvent _event;

  static bool _inited = false;

  static bool _isStartup = false;

  static AppLifecycleStateObserver _observer =
  new AppLifecycleStateObserver(_channel);

  static void onNfcEvent(OnNfcEvent event) {
    _event = event;
  }

  static Future sendStr() {
    return _channel.invokeMethod("sendStr", "00a40000023f00");
  }

  static Future sendHex() {
    Uint8List list = Uint8List.fromList("00a40000023f00".codeUnits);
    return _channel.invokeMethod("sendHex", list);
  }

  /// is nfc available ?
  static Future<bool> isAvailable() {
    if (Platform.isAndroid) {
      return _channel.invokeMethod('isAvailable');
    }
    return new Future.value(false);
  }

  /// is nfc is available and is enabled ?
  static Future<bool> isEnabled() {
    if (Platform.isAndroid) {
      return _channel.invokeMethod('isEnabled');
    }
    return new Future.value(false);
  }

  /// startup the nfc system listener
  static Future startup() async {
    if (!_inited) {
      _channel.setMethodCallHandler(handler);
    }
    var res = await _channel.invokeMethod('startup');
    if (res['code'] != null) {
      throw new NfcError(code: res['code']);
    } else {
      _isStartup = true;
    }
  }

  /// stop listen nfc events
  static Future shutdown() async {
    await _channel.invokeMethod('shutdown');
    _isStartup = false;
  }




  static Future handler(MethodCall call) {
    String name = call.method;
    final data = call.arguments;
    switch (name) {
      case "nfc":
        print(data);
        if (_event != null) {
          String tech = data['tech'];
          NfcEvent event;
          if (tech == 'IsoDep') {
            event = new NfcEvent(new IsoDep(channel: _channel, info: { 'tech': data['tech'], 'id': data['id'] }));
          } else if (tech == "MifareClassic"){
            event = new NfcEvent(new MifareClassic(channel: _channel, info:  { 'tech': data['tech'], 'id': data['id'] }));
          }
          _event(event);
        }
        break;
    }
  }
}
