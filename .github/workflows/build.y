
name: Build Minuteyar APK

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Setup Java
        uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: '17'

      - name: Setup Gradle
        uses: gradle/actions/setup-gradle@v4
        with:
          gradle-version: '8.9'

      - name: Create Android project
        shell: bash
        run: |
          mkdir -p app/src/main/java/com/minuteyar/app
          mkdir -p app/src/main/res/xml
          mkdir -p app/src/main/res/values

          cat > settings.gradle <<'EOF'
          pluginManagement {
              repositories {
                  google()
                  mavenCentral()
                  gradlePluginPortal()
              }
          }
          dependencyResolutionManagement {
              repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
              repositories {
                  google()
                  mavenCentral()
              }
          }
          rootProject.name = "Minuteyar"
          include(":app")
          EOF

          cat > build.gradle <<'EOF'
          plugins {
              id 'com.android.application' version '8.7.3' apply false
          }
          EOF

          cat > app/build.gradle <<'EOF'
          plugins {
              id 'com.android.application'
          }

          android {
              namespace 'com.minuteyar.app'
              compileSdk 35

              defaultConfig {
                  applicationId 'com.minuteyar.app'
                  minSdk 23
                  targetSdk 29
                  versionCode 1
                  versionName '1.0'
              }
          }
          EOF

          cat > app/src/main/res/values/strings.xml <<'EOF'
          <resources>
              <string name="app_name">دقیه‌یار</string>
              <string name="accessibility_description">خواندن متن پیشنهاد سفر برای محاسبه نرخ دقیقه</string>
          </resources>
          EOF

          cat > app/src/main/res/xml/accessibility_service.xml <<'EOF'
          <accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
              android:description="@string/accessibility_description"
              android:accessibilityEventTypes="typeWindowContentChanged|typeWindowStateChanged"
              android:accessibilityFeedbackType="feedbackGeneric"
              android:notificationTimeout="100"
              android:canRetrieveWindowContent="true"
              android:canPerformGestures="false"
              android:canRequestFilterKeyEvents="false" />
          EOF

          cat > app/src/main/AndroidManifest.xml <<'EOF'
          <manifest xmlns:android="http://schemas.android.com/apk/res/android">

              <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW"/>

              <application
                  android:label="@string/app_name"
                  android:theme="@android:style/Theme.Material.Light.NoActionBar"
                  android:allowBackup="false">

                  <activity
                      android:name=".MainActivity"
                      android:exported="true">
                      <intent-filter>
                          <action android:name="android.intent.action.MAIN"/>
                          <category android:name="android.intent.category.LAUNCHER"/>
                      </intent-filter>
                  </activity>

                  <service
                      android:name=".RideAccessibilityService"
                      android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"
                      android:exported="false">
                      <intent-filter>
                          <action android:name="android.accessibilityservice.AccessibilityService"/>
                      </intent-filter>
                      <meta-data
                          android:name="android.accessibilityservice"
                          android:resource="@xml/accessibility_service"/>
                  </service>

              </application>
          </manifest>
          EOF

          cat > app/src/main/java/com/minuteyar/app/MainActivity.kt <<'EOF'
          package com.minuteyar.app

          import android.app.Activity
          import android.os.Bundle
          import android.content.Intent
          import android.provider.Settings
          import android.net.Uri
          import android.widget.Button
          import android.widget.LinearLayout
          import android.widget.TextView

          class MainActivity : Activity() {
              override fun onCreate(savedInstanceState: Bundle?) {
                  super.onCreate(savedInstanceState)

                  val layout = LinearLayout(this)
                  layout.orientation = LinearLayout.VERTICAL
                  layout.setPadding(32, 48, 32, 32)

                  val title = TextView(this)
                  title.text = "دقیه‌یار\\n\\nمحاسبه نرخ کرایه به دقیقه"
                  title.textSize = 24f
                  layout.addView(title)

                  val accessibility = Button(this)
                  accessibility.text = "فعال‌سازی دسترسی خواندن متن"
                  accessibility.setOnClickListener {
                      startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                  }
                  layout.addView(accessibility)

                  val overlay = Button(this)
                  overlay.text = "اجازه نمایش روی برنامه‌ها"
                  overlay.setOnClickListener {
                      if (!Settings.canDrawOverlays(this)) {
                          startActivity(
                              Intent(
                                  Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                  Uri.parse("package:$packageName")
                              )
                          )
                      }
                  }
                  layout.addView(overlay)

                  val info = TextView(this)
                  info.text = "\\nابتدا دسترسی خواندن متن را فعال کنید.\\nسپس اجازه نمایش شناور را بدهید."
                  info.textSize = 16f
                  layout.addView(info)

                  setContentView(layout)
              }
          }
          EOF

          cat > app/src/main/java/com/minuteyar/app/RideAccessibilityService.kt <<'EOF'
          package com.minuteyar.app

          import android.accessibilityservice.AccessibilityService
          import android.view.accessibility.AccessibilityEvent
          import android.view.accessibility.AccessibilityNodeInfo
          import android.graphics.PixelFormat
          import android.view.WindowManager
          import android.view.Gravity
          import android.view.View
          import android.widget.TextView
          import android.graphics.Color

          class RideAccessibilityService : AccessibilityService() {

              private var overlay: TextView? = null
              private lateinit var wm: WindowManager

              override fun onServiceConnected() {
                  super.onServiceConnected()
                  wm = getSystemService(WINDOW_SERVICE) as WindowManager
              }

              override fun onAccessibilityEvent(event: AccessibilityEvent?) {
                  if (event == null) return
                  val root = rootInActiveWindow ?: return

                  val texts = StringBuilder()
                  collectText(root, texts)

                  val content = texts.toString()
                  if (content.isNotBlank()) showOverlay(content)
              }

              private fun collectText(node: AccessibilityNodeInfo?, out: StringBuilder) {
                  if (node == null) return

                  node.text?.let {
                      if (it.isNotBlank()) out.append(it).append("\\n")
                  }

                  node.contentDescription?.let {
                      if (it.isNotBlank()) out.append(it).append("\\n")
                  }

                  for (i in 0 until node.childCount) {
                      collectText(node.getChild(i), out)
                  }
              }

              private fun showOverlay(content: String) {
                  if (!android.provider.Settings.canDrawOverlays(this)) return

                  val amount = Regex("""([0-9۰-۹٠-٩,]+)\s*(?:تومان|ریال)""")
                      .find(content)

                  val minutes = Regex("""([0-9۰-۹٠-٩]+)\s*دقیقه""")
                      .find(content)

                  val digits = amount?.groupValues?.get(1)
                      ?.replace(",", "")
                      ?.replace("۰", "0")
                      ?.replace("۱", "1")
                      ?.replace("۲", "2")
                      ?.replace("۳", "3")
                      ?.replace("۴", "4")
                      ?.replace("۵", "5")
                      ?.replace("۶", "6")
                      ?.replace("۷", "7")
                      ?.replace("۸", "8")
                      ?.replace("۹", "9")
                      ?.replace("٠", "0")
                      ?.replace("١", "1")
                      ?.replace("٢", "2")
                      ?.replace("٣", "3")
                      ?.replace("٤", "4")
                      ?.replace("٥", "5")
                      ?.replace("٦", "6")
                      ?.replace("٧", "7")
                      ?.replace("٨", "8")
                      ?.replace("٩", "9")

                  val minuteText = minutes?.groupValues?.get(1)
                      ?.replace("۰", "0")
                      ?.replace("۱", "1")
                      ?.replace("۲", "2")
                      ?.replace("۳", "3")
                      ?.replace("۴", "4")
                      ?.replace("۵", "5")
                      ?.replace("۶", "6")
                      ?.replace("۷", "7")
                      ?.replace("۸", "8")
                      ?.replace("۹", "9")
                      ?.replace("٠", "0")
                      ?.replace("١", "1")
                      ?.replace("٢", "2")
                      ?.replace("٣", "3")
                      ?.replace("٤", "4")
                      ?.replace("٥", "5")
                      ?.replace("٦", "6")
                      ?.replace("٧", "7")
                      ?.replace("٨", "8")
                      ?.replace("٩", "9")

                  val rate = if (digits != null && minuteText != null) {
                      val m = minuteText.toIntOrNull()
                      val f = digits.toLongOrNull()
                      if (m != null && m > 0 && f != null) f / m else null
                  } else null

                  val display = if (rate != null) {
                      "دقیه‌یار\\n${rate} تومان/دقیقه"
                  } else {
                      "دقیه‌یار\\nدر انتظار پیشنهاد... "
                  }

                  if (overlay == null) {
                      overlay = TextView(this).apply {
                          setTextColor(Color.WHITE)
                          setBackgroundColor(0xDD222222.toInt())
                          textSize = 18f
                          setPadding(24, 16, 24, 16)
                      }

                      val params = WindowManager.LayoutParams(
                          WindowManager.LayoutParams.WRAP_CONTENT,
                          WindowManager.LayoutParams.WRAP_CONTENT,
                          WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
                          WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                              WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                          PixelFormat.TRANSLUCENT
                      )
                      params.gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                      params.y = 120

                      wm.addView(overlay, params)
                  }

                  overlay?.text = display
              }

              override fun onInterrupt() {}
          }
          EOF

      - name: Build APK
        run: gradle assembleDebug

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: minuteyar-apk
          path: app/build/outputs/apk/debug/app-debug.apk
  
