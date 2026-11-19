import 'package:flutter/material.dart';

/// iBetoo Media design tokens. One editorial system shared across all views.
class MediaPalette {
  static const orange=Color(0xffff6840);
  static const orangeDeep=Color(0xffe04c20);
  static const ink=Color(0xff172027);
  static const cream=Color(0xfffaf8f5);
  static const dark=Color(0xff0d1116);
  static const darkSurface=Color(0xff1b222b);
  static const divider=Color(0xffeae6e1);
  static const muted=Color(0xff84909b);
  static const mint=Color(0xff24bf9f);
}

ThemeData mediaTheme(Brightness brightness) {
  final night=brightness==Brightness.dark;
  final base=ColorScheme.fromSeed(
    seedColor:MediaPalette.orange,brightness:brightness);
  final panel=night?MediaPalette.darkSurface:Colors.white;
  final bg=night?MediaPalette.dark:MediaPalette.cream;
  final foreground=night?const Color(0xfff5f5f4):MediaPalette.ink;
  final subtitle=night?const Color(0xffa8aeb8):const Color(0xff72767e);
  final divider=night?const Color(0xff2f3740):MediaPalette.divider;
  final outline=RoundedRectangleBorder(
    borderRadius:BorderRadius.circular(19),
    side:BorderSide(color:divider,width:1));

  final scheme=base.copyWith(
    primary:MediaPalette.orange,
    onPrimary:Colors.white,
    secondary:MediaPalette.mint,
    surface:bg,
    onSurface:foreground,
    outline:divider,
    surfaceContainerLow:panel,
    surfaceContainer:night?const Color(0xff202730):const Color(0xfff3f0ec),
    surfaceContainerHigh:night?const Color(0xff252c35):const Color(0xffefebe5),
  );

  return ThemeData(
    useMaterial3:true,
    brightness:brightness,
    colorScheme:scheme,
    scaffoldBackgroundColor:bg,
    dividerColor:divider,
    splashColor:MediaPalette.orange.withValues(alpha:.07),
    highlightColor:MediaPalette.orange.withValues(alpha:.04),
    iconTheme:IconThemeData(color:foreground,size:23),
    textTheme:TextTheme(
      headlineLarge:TextStyle(color:foreground,fontSize:34,
        height:1.25,fontWeight:FontWeight.w900,letterSpacing:-.5),
      headlineSmall:TextStyle(color:foreground,fontSize:23,
        fontWeight:FontWeight.w900,height:1.25),
      titleLarge:TextStyle(color:foreground,fontSize:21,
        fontWeight:FontWeight.w800,height:1.3),
      titleMedium:TextStyle(color:foreground,fontSize:15,
        fontWeight:FontWeight.w800,height:1.35),
      bodyLarge:TextStyle(color:foreground,fontSize:15,height:1.5),
      bodyMedium:TextStyle(color:foreground,fontSize:13,height:1.65),
      bodySmall:TextStyle(color:subtitle,fontSize:11,height:1.5),
      labelLarge:const TextStyle(fontWeight:FontWeight.w900,fontSize:13),
    ),
    appBarTheme:AppBarTheme(
      backgroundColor:bg,
      surfaceTintColor:Colors.transparent,
      foregroundColor:foreground,
      scrolledUnderElevation:0,
      elevation:0,
      centerTitle:false,
      toolbarHeight:66,
      titleTextStyle:TextStyle(color:foreground,fontSize:20,
        fontWeight:FontWeight.w900,letterSpacing:-.35),
    ),
    cardTheme:CardThemeData(
      color:panel,surfaceTintColor:Colors.transparent,elevation:0,
      margin:EdgeInsets.zero,shape:outline,
    ),
    dialogTheme:DialogThemeData(
      backgroundColor:panel,surfaceTintColor:Colors.transparent,
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(26)),
    ),
    bottomSheetTheme:BottomSheetThemeData(
      backgroundColor:panel,
      modalBackgroundColor:panel,
      showDragHandle:true,
      shape:const RoundedRectangleBorder(
        borderRadius:BorderRadius.vertical(top:Radius.circular(26))),
    ),
    inputDecorationTheme:InputDecorationTheme(
      filled:true,
      fillColor:night?const Color(0xff242a32):const Color(0xfff2f0ed),
      prefixIconColor:subtitle,
      hintStyle:TextStyle(color:subtitle,fontSize:13),
      contentPadding:const EdgeInsets.symmetric(
        horizontal:18,vertical:17),
      border:OutlineInputBorder(borderRadius:BorderRadius.circular(17),
        borderSide:BorderSide.none),
      enabledBorder:OutlineInputBorder(
        borderRadius:BorderRadius.circular(17),
        borderSide:BorderSide(color:divider)),
      focusedBorder:OutlineInputBorder(
        borderRadius:BorderRadius.circular(17),
        borderSide:const BorderSide(color:MediaPalette.orange,width:1.7)),
      errorBorder:OutlineInputBorder(
        borderRadius:BorderRadius.circular(17),
        borderSide:const BorderSide(color:Colors.red)),
    ),
    filledButtonTheme:FilledButtonThemeData(
      style:FilledButton.styleFrom(
        backgroundColor:MediaPalette.orange,
        foregroundColor:Colors.white,
        minimumSize:const Size(0,49),
        elevation:0,
        padding:const EdgeInsets.symmetric(horizontal:18,vertical:12),
        shape:RoundedRectangleBorder(
          borderRadius:BorderRadius.circular(15)),
        textStyle:const TextStyle(fontWeight:FontWeight.w900,fontSize:13)),
    ),
    outlinedButtonTheme:OutlinedButtonThemeData(
      style:OutlinedButton.styleFrom(
        foregroundColor:MediaPalette.orange,
        side:BorderSide(color:divider),
        minimumSize:const Size(0,49),
        shape:RoundedRectangleBorder(
          borderRadius:BorderRadius.circular(15))),
    ),
    floatingActionButtonTheme:const FloatingActionButtonThemeData(
      backgroundColor:MediaPalette.orange,
      foregroundColor:Colors.white,elevation:3),
    navigationBarTheme:NavigationBarThemeData(
      backgroundColor:panel,
      elevation:0,height:74,
      indicatorColor:MediaPalette.orange.withValues(alpha:.14),
      labelTextStyle:WidgetStatePropertyAll(
        TextStyle(color:foreground,fontWeight:FontWeight.w800,fontSize:11)),
      iconTheme:WidgetStatePropertyAll(
        IconThemeData(color:foreground,size:24)),
    ),
    tabBarTheme:TabBarThemeData(
      labelColor:MediaPalette.orange,
      unselectedLabelColor:subtitle,
      labelStyle:const TextStyle(fontSize:13,fontWeight:FontWeight.w900),
      unselectedLabelStyle:const TextStyle(fontSize:13),
      indicatorColor:MediaPalette.orange,
      dividerColor:divider,
      indicatorSize:TabBarIndicatorSize.tab,
    ),
    snackBarTheme:SnackBarThemeData(
      behavior:SnackBarBehavior.floating,
      backgroundColor:night?const Color(0xff2b333e):MediaPalette.ink,
      contentTextStyle:const TextStyle(color:Colors.white,fontSize:13),
      shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(12))),
  );
}
