import 'package:flutter/material.dart';
import 'common.dart';

/// 购件助手"我的"页。
///
/// 当前阶段为空白占位：原文析助手的完整设置页（下载设置/链接识别/
/// 实验功能/备份/帮助诊断）随网盘与传输业务一并移除，后续在此承载
/// 购件助手的账号与会话管理。
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/icons/app.png', width: 56, height: 56),
          const SizedBox(height: 14),
          const Text(
            '购件助手',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '设置功能建设中',
            style: TextStyle(fontSize: 12.5, color: secondary(context)),
          ),
        ],
      ),
    );
  }
}
