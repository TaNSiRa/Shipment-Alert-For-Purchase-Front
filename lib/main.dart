import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:universal_html/html.dart' as html;

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/realtime_client.dart';

part 'layout/app_shell.dart';
part 'layout/navigation.dart';
part 'layout/topbar.dart';
part 'layout/scroll_behavior.dart';
part 'pages/login_page.dart';
part 'pages/account_gates.dart';
part 'pages/dashboard_page.dart';
part 'pages/po_table_page.dart';
part 'pages/po_detail_dialog.dart';
part 'pages/po_actions.dart';
part 'pages/po_import_dialog.dart';
part 'pages/po_create_dialog.dart';
part 'pages/roadmap_page.dart';
part 'pages/calendar_page.dart';
part 'pages/workflow_page.dart';
part 'pages/masters_page.dart';
part 'pages/users_page.dart';
part 'pages/settings_page.dart';
part 'pages/profile_page.dart';
part 'shared/design.dart';
part 'shared/liquid_glass.dart';
part 'shared/smooth_scroll.dart';
part 'shared/scroll_tooltip_guard.dart';
part 'shared/toast.dart';
part 'shared/searchable_dropdown.dart';
part 'shared/page_components.dart';
part 'shared/helpers.dart';
part 'shared/charts.dart';

void main() {
  // Each wheel notch becomes a short glide instead of a jump (RAP).
  SmoothScrollBinding.ensureInitialized();
  // Release builds swallow framework errors (a broken widget just turns grey).
  // Send them to the browser console so a problem on a user's PC can be seen
  // with F12 instead of guessed at.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    html.window.console.error('[PSA] ${details.exceptionAsString()}\n${details.stack}');
  };
  // Open in whichever theme (liquid glass / flat) was left on.
  Lg.restore();
  LiquidField.ensure();
  runApp(const PurchaseShipmentAlertApp());
}

class PurchaseShipmentAlertApp extends StatelessWidget {
  const PurchaseShipmentAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Lg.enabled,
      builder: (context, liquid, _) => _app(liquid),
    );
  }

  Widget _app(bool liquid) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Purchase Shipment Alert',
      scrollBehavior: const AppScrollBehavior(),
      // Above the Navigator, so every page, dialog and overlay in the app is
      // inside it: a scroll anywhere silences tooltips until it settles. See
      // shared/scroll_tooltip_guard.dart for what it is protecting against.
      builder: (context, child) =>
          DsScrollTooltipGuard(child: child ?? const SizedBox.shrink()),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: DsColors.navy, brightness: Brightness.light),
        scaffoldBackgroundColor: DsColors.scaffold,
        fontFamily: dsFontSans,
        // Covers every style that inherits from the theme; the handful of
        // styles below that name a family outright repeat it. See
        // dsFontFallback in shared/design.dart for why this matters offline.
        fontFamilyFallback: dsFontFallback,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          // Fields are lit panes too, not white cut-outs — inside a glass card
          // an opaque white input is the one thing that still reads as paper.
          fillColor: DsColors.glass,
          isDense: true,
          hintStyle: const TextStyle(color: DsColors.faint2, fontWeight: FontWeight.w400),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: DsColors.inputBorder)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: DsColors.inputBorder)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: DsColors.navy, width: 1.6)),
          errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: DsColors.redFg, width: 1.4)),
          focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: DsColors.redFg, width: 1.8)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: DsColors.navy,
            foregroundColor: Colors.white,
            minimumSize: const Size(44, 42),
            textStyle: const TextStyle(
                fontWeight: FontWeight.w600, fontFamily: dsFontSans, fontFamilyFallback: dsFontFallback),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: DsColors.text,
            minimumSize: const Size(44, 42),
            side: const BorderSide(color: DsColors.inputBorder, width: 1.4),
            textStyle: const TextStyle(
                fontWeight: FontWeight.w600, fontFamily: dsFontSans, fontFamilyFallback: dsFontFallback),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: DsColors.navy),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: DsColors.chip,
          side: const BorderSide(color: DsColors.cardBorder),
          labelStyle: const TextStyle(fontSize: 12, color: DsColors.muted, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        dividerTheme: const DividerThemeData(color: DsColors.line, thickness: 1, space: 1),
        // ── The scrollbar. ──
        //
        // Material's web default is a chunky opaque grey slab with square ends,
        // parked down the side of every page whether anything is happening or
        // not. It is the single most-looked-at control in a system built out of
        // long tables, and it was the last piece of stock Material still
        // showing through the glass.
        //
        // What it is instead: a 6 px hairline that FADES OUT when scrolling
        // stops (`thumbVisibility` false — the Scrollbar handles the fade), then
        // widens to 11 px and darkens when the pointer comes near, so it is out
        // of the way while reading and a real handle the moment it is wanted.
        // `interactive` makes that handle draggable, which the default on web
        // leaves off.
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.dragged)) return DsColors.scrollThumbDrag;
            if (states.contains(WidgetState.hovered)) return DsColors.scrollThumbHover;
            return DsColors.scrollThumb;
          }),
          thickness: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.dragged) || states.contains(WidgetState.hovered)) {
              return 11.0;
            }
            return 6.0;
          }),
          // The channel appears with the widened thumb and not before, so the
          // resting state is one hairline rather than a line inside a groove.
          trackColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ? DsColors.scrollTrack : Colors.transparent),
          trackBorderColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ? DsColors.scrollTrackBorder : Colors.transparent),
          trackVisibility: const WidgetStatePropertyAll(true),
          radius: const Radius.circular(8),
          crossAxisMargin: 3,
          mainAxisMargin: 6,
          // A short page must not produce a stubby 8 px thumb that cannot be
          // grabbed; a long one must not produce a thumb so short it disappears.
          minThumbLength: 44,
          interactive: true,
        ),
        // Selection in the app's own indigo rather than the framework's blue —
        // including the drag handles, which are what show on a touch screen.
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: DsColors.selection,
          cursorColor: DsColors.navy,
          selectionHandleColor: DsColors.navy,
        ),
        // Every dropped menu, from the ones that name their own colour to the
        // ones that never did — one opaque surface, same as the dialogs.
        popupMenuTheme: PopupMenuThemeData(
          color: DsColors.popupSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(DsColors.popupSurface),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
        dialogTheme: DialogThemeData(
          // Opaque, unlike everything else — see [DsColors.popupSurface]. Every
          // AlertDialog in the app inherits its surface from here, so this line
          // is what keeps the plain ones (edit request detail, add todo, the
          // period picker) from turning into windows onto the page behind.
          backgroundColor: DsColors.popupSurface,
          surfaceTintColor: Colors.transparent,
          elevation: 24,
          shadowColor: const Color(0x331c1630),
          shape: liquid
              ? LiquidShape(borderRadius: BorderRadius.circular(Lg.r(20)))
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: DsColors.glassEdge),
                ),
          titleTextStyle: const TextStyle(
              fontFamily: dsFontSans,
              fontFamilyFallback: dsFontFallback,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: DsColors.heading),
          contentTextStyle: const TextStyle(
              fontFamily: dsFontSans,
              fontFamilyFallback: dsFontFallback,
              fontSize: 13.5,
              color: DsColors.text,
              height: 1.5),
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: DsColors.popupSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          headerBackgroundColor: DsColors.navy,
          headerForegroundColor: Colors.white,
          todayBorder: const BorderSide(color: DsColors.navy),
          dayShape: const WidgetStatePropertyAll(CircleBorder()),
        ),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}
