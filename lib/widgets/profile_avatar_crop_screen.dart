import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:mixroom/helpers/app_popup.dart';
import 'package:mixroom/l10n/l10n.dart';
import 'package:mixroom/widgets/account_glass_ui.dart';

class ProfileAvatarCropScreen extends StatefulWidget {
  const ProfileAvatarCropScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<ProfileAvatarCropScreen> createState() =>
      _ProfileAvatarCropScreenState();
}

class _ProfileAvatarCropScreenState extends State<ProfileAvatarCropScreen> {
  final CropController _controller = CropController();
  var _busy = false;
  var _ready = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: const Color(0xFF1D2124),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(
                          L10n.translate(context, 'Cancel'),
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: kAccountGlassText,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          L10n.translate(context, 'Change photo'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            color: kAccountGlassText,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 72),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Crop(
                    image: widget.imageBytes,
                    controller: _controller,
                    withCircleUi: true,
                    interactive: true,
                    fixCropRect: true,
                    baseColor: const Color(0xFF1D2124),
                    maskColor: Colors.black.withValues(alpha: 0.62),
                    progressIndicator: const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Color(0xFFF4F4F4),
                      ),
                    ),
                    onStatusChanged: (status) {
                      final ready = status == CropStatus.ready;
                      if (ready == _ready) return;
                      setState(() => _ready = ready);
                    },
                    cornerDotBuilder: (size, edgeAlignment) =>
                        const SizedBox.shrink(),
                    onCropped: _onCropped,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: (_busy || !_ready) ? null : _usePhoto,
                      borderRadius: BorderRadius.circular(26),
                      child: Ink(
                        decoration: BoxDecoration(
                          color: kAccountGlassBlue.withValues(
                            alpha: (_busy || !_ready) ? 0.45 : 1,
                          ),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Center(
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Color(0xFFF4F4F4),
                                  ),
                                )
                              : Text(
                                  L10n.translate(context, 'Use photo'),
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    color: Color(0xFFF4F4F4),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _usePhoto() {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    _controller.crop();
  }

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        if (!mounted) return;
        Navigator.of(context).pop(croppedImage);
      case CropFailure():
        if (!mounted) return;
        setState(() => _busy = false);
        showAppSnackBar(context, "Couldn't read that image.");
    }
  }
}
