import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'vap_controller.dart';
import 'vap_view.dart';

class VapViewForIos extends StatelessWidget {
  final void Function(VapController controller) onControllerCreated;
  final VapScaleFit fit;
  final void Function(dynamic event)? onEvent;

  VapViewForIos(
      {required this.onControllerCreated,
      required this.fit,
      this.onEvent});

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> creationParams = <String, dynamic>{
      'scaleType': fit.name
    };
    return UiKitView(
      viewType: "flutter_vap",
      layoutDirection: TextDirection.ltr,
      creationParams: creationParams,
      creationParamsCodec: StandardMessageCodec(),
      onPlatformViewCreated: (viewId) async{
        await Future.delayed(const Duration(milliseconds: 1000));
        onControllerCreated(VapController(
          viewId: viewId,
          onEvent: onEvent,
        ));
      },
    );
  }
}
