import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_vap/flutter_vap.dart';
import 'package:flutter_vap/vap_view_for_android.dart';
import 'package:flutter_vap/vap_view_for_ios.dart';

class VapView extends StatefulWidget {
  final void Function(VapController controller) onControllerCreated;
  final VapScaleFit fit;
  final void Function(dynamic event)? onEvent;

  const VapView({
    super.key,
    required this.onControllerCreated,
    this.fit = VapScaleFit.FIT_CENTER,
    this.onEvent,
  });

  @override
  State<VapView> createState() => _VapViewState();
}

class _VapViewState extends State<VapView> {
  VapController? controller;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return VapViewForAndroid(
        onControllerCreated: onControllerCreated,
        fit: widget.fit,
        onEvent: widget.onEvent,
      );
    } else if (Platform.isIOS) {
      return VapViewForIos(
        onControllerCreated: onControllerCreated,
        fit: widget.fit,
        onEvent: widget.onEvent,
      );
    }
    return Container();
  }

  void onControllerCreated(VapController controller) {
    this.controller = controller;
    widget.onControllerCreated(controller);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

enum VapScaleFit {
  FIT_XY,
  FIT_CENTER,
  CENTER_CROP,
}
