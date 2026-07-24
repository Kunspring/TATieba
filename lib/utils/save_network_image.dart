import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:gal/gal.dart';

import '../widgets/app_toast.dart';

const _imageHeaders = {'Referer': 'https://tieba.baidu.com/'};

Future<void> saveNetworkImage(BuildContext context, String url) async {
  try {
    final file = await DefaultCacheManager().getSingleFile(
      url,
      headers: _imageHeaders,
    );
    final bytes = await file.readAsBytes();
    final name = 'tieba_img_${DateTime.now().millisecondsSinceEpoch}';
    await Gal.putImageBytes(bytes, name: name);
    if (context.mounted) {
      showAppToast(context, '已保存到相册', type: AppToastType.success);
    }
  } catch (_) {
    if (context.mounted) {
      showAppToast(context, '保存失败', type: AppToastType.error);
    }
  }
}
