package com.tallerneto.mecanico

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Canal del instalador de actualizaciones (lo usa lib/servicios/
/// actualizacion.dart): abre el instalador del sistema con el APK
/// descargado y gestiona el permiso de «instalar apps desconocidas».
/// Mismo patrón probado en la app de RutaNeto.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tallerneto/instalador")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "instalar" -> {
                        val ruta = call.argument<String>("ruta")
                        if (ruta == null) {
                            result.error("SIN_RUTA", "Falta la ruta del APK", null)
                            return@setMethodCallHandler
                        }
                        val archivo = File(ruta)
                        if (!archivo.exists()) {
                            result.error("NO_EXISTE", "El APK descargado no existe", null)
                            return@setMethodCallHandler
                        }
                        val uri: Uri = FileProvider.getUriForFile(
                            this, "${applicationContext.packageName}.fileprovider", archivo
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "puedeInstalar" -> {
                        // Antes de Android 8 (API 26) no existe este permiso.
                        val puede = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else {
                            true
                        }
                        result.success(puede)
                    }
                    "abrirAjustesInstalar" -> {
                        try {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // Respaldo: ajustes de seguridad generales.
                            try {
                                startActivity(
                                    Intent(Settings.ACTION_SECURITY_SETTINGS)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("SIN_AJUSTES", "No se pudieron abrir los ajustes", null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
