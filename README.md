# Blood Detection & Segmentation Mobile App

A Flutter-based mobile application for blood detection and segmentation using yolo and  mobilenetV3 models. The application allows users to select or capture an image, perform AI inference on-device, and display the prediction results.

## Features

- Blood detection using a lightweight AI model
- Blood segmentation with heatmap visualization
- Capture images using the camera
- Select images from the gallery
- Fast on-device inference with TensorFlow Lite
- User-friendly interface

---

## Application Screenshots

<img width="150.5" height="400" alt="WhatsApp Image 2026-07-12 at 7 32 47 PM" src="https://github.com/user-attachments/assets/9a7585ca-eae8-4dbe-95c4-5d7d6883b3e6" />
<img width="150.5" height="400" alt="WhatsApp Image 2026-07-12 at 7 32 47 PM (1)" src="https://github.com/user-attachments/assets/961fccbd-9c84-49ba-ab39-95f7e5452376" />
<img width="150.5" height="400" alt="WhatsApp Image 2026-07-12 at 7 32 47 PM (2)" src="https://github.com/user-attachments/assets/046325b5-ac67-43d0-b87c-d8f31eb00b55" />
<img width="150.5" height="400" alt="WhatsApp Image 2026-07-12 at 7 32 48 PM" src="https://github.com/user-attachments/assets/2b716e04-c7a5-47fa-a608-90b5c8318959" />
<img width="150.5" height="400" alt="WhatsApp Image 2026-07-12 at 7 32 48 PM (1)" src="https://github.com/user-attachments/assets/3a44cc39-9663-4b74-9e2e-fd78af82eb58" />
<img width="150.5" height="400" alt="WhatsApp Image 2026-07-12 at 7 32 49 PM" src="https://github.com/user-attachments/assets/68639b80-48ee-4a13-90cd-d60f0eb017fd" />



---


# Requirements

Before running the project, make sure the following software is installed:

- Flutter **3.29.0**
- Dart SDK (included with Flutter)
- Android Studio **Latest**
- VS Code
- Android SDK
- Git

---

# Clone the Repository

```bash
git clone https://github.com/chbanti/Real-Time-Blood-Detection-System/tree/master
```

---

# Verify Flutter Installation

Open a terminal and run:

```bash
flutter doctor
```




---

# Run the Application

Open the project in **VS Code**.

Open a terminal and run:

```bash
flutter run
```

Or press **F5** in VS Code.

---

# Build APK

Debug APK:

```bash
flutter build apk
```

Release APK:

```bash
flutter build apk --release
```

The generated APK will be available at:

```
build/app/outputs/flutter-apk/
```

---

# Assets

Ensure all required assets are included in the `assets/` directory and correctly listed in `pubspec.yaml`.

Example:

```yaml
flutter:
  assets:
    - assets/images/
    - assets/models/
```

---


# Notes

- Make sure the required AI model files are placed in the correct `assets/models/` directory.
- If dependencies change, run:

```bash
flutter pub get
```

- If build issues occur, clean the project:

```bash
flutter clean
flutter pub get
```

---

# Author

**Muhammad Shahroz**

Embedded Software Engineer 

---
