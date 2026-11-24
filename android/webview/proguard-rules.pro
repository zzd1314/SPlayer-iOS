# 保留 JS 桥接方法不被混淆
-keepclassmembers class com.splayer.next.web.SPlayerBridge$Native {
    public *;
}
-keep class com.splayer.next.web.** { *; }