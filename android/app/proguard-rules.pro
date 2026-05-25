# Keep Retrofit / kotlinx.serialization metadata.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keep,includedescriptorclasses class org.neiam.waxx.app.**$$serializer { *; }
-keepclassmembers class org.neiam.waxx.app.** {
    *** Companion;
}
-keepclasseswithmembers class org.neiam.waxx.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}
