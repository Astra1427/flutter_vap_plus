import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'vap_controller.dart';
import 'vap_view.dart';

class VapViewForAndroid extends StatelessWidget {
  final void Function(VapController controller) onControllerCreated;
  final VapScaleFit fit;
  final int repeatCount;
  final void Function(dynamic event,dynamic arguments)? onEvent;
  final void Function(Object error)? onError;

  VapViewForAndroid(
      {required this.onControllerCreated,
      required this.fit,
        required  this.repeatCount,
      this.onEvent,
      this.onError});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> creationParams = <String, dynamic>{
      'scaleType': fit.name,
      'repeatCount' : repeatCount
    };
    return AndroidView(
      viewType: "flutter_vap",
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: StandardMessageCodec(),
      onPlatformViewCreated: (viewId) async{
        await Future.delayed(const Duration(milliseconds: 1000));
        onControllerCreated(VapController(
          viewId: viewId,
          onEvent: onEvent
        ));
      },
    );
  }
}
