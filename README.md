# 🩸 BloodConnect — Blood Donation & Emergency Request App

**Connecting Blood Donors with People in Need**

BloodConnect is a cross-platform blood donation application developed using Flutter and Firebase. It aims to simplify the process of finding compatible blood donors by connecting donors with patients or their families who need blood.

The application allows users to register, manage their accounts, submit blood requests, and search for eligible donors based on blood group, city, and donor availability.

## 📌 Table of Contents

- [Project Overview](#-project-overview)
- [Objectives](#-objectives)
- [Key Features](#-key-features)
- [User Roles](#-user-roles)
- [How the Application Works](#-how-the-application-works)
- [System Architecture](#-system-architecture)
- [Technology Stack](#-technology-stack)
- [Database Structure](#-database-structure)
- [Project Structure](#-project-structure)
- [Installation and Setup](#-installation-and-setup)
- [Current Development Status](#-current-development-status)
- [Future Improvements](#-future-improvements)
- [Contributing](#-contributing)
- [License](#-license)

## 📖 Project Overview

BloodConnect is designed to make blood donor discovery more accessible and organized. In emergencies, finding a suitable donor quickly can be challenging. BloodConnect provides a digital platform where people can submit blood requirements and discover donors who match their blood group and location.

The application uses Flutter for its user interface and Firebase services for authentication and cloud data management.

The project is being developed with Android and iOS support in mind, with the initial focus on users in Pakistan.

## 🎯 Objectives

- Make it easier to find potential blood donors.
- Connect blood requesters with compatible donors.
- Organize blood requests and donor information.
- Provide secure user authentication and role-based access.
- Support the management of donor availability and request status.
- Establish a foundation for future notifications and administrative tools.

## ✨ Key Features

### 1. User Authentication
- User registration and login.
- Firebase Authentication with email and password.
- Password reset functionality.
- User profile data stored in Cloud Firestore.
- Role-based navigation for donors and receivers.
- Logout functionality.

### 2. Donor Management
- Donor registration and profile information.
- Blood group and city-based donor discovery.
- Donor availability and active-status filtering.
- Donor profiles linked to user accounts.

### 3. Blood Request Management
- Create a blood request.
- Specify the patient's name, required blood group, units, hospital, city, urgency, required date, and additional details.
- Save request information in Cloud Firestore.
- Open the donor discovery screen after creating a request.

### 4. Find Donors
- Search for donors by blood group.
- Filter donors by city and availability.
- Display matching donor profiles.
- Associate donor discovery with a specific blood request.

### 5. Donor Request Workflow
- Create a donor request associated with a blood request.
- Check request ownership and pending status.
- Verify donor availability and blood group/city compatibility.
- Prevent duplicate pending or accepted requests for the same donor and blood request.

### 6. User Interface
- Flutter-based cross-platform interface.
- Splash screen and onboarding flow.
- Separate navigation and dashboards based on user roles.
- Blood group selection and request forms.

## 👥 User Roles

### Donor
A donor can create an account, provide personal and blood group information, manage availability where supported, and be discovered through the donor search process.

### Receiver / Requester
A receiver can register, submit blood requirements, provide hospital and location details, and search for potential donors matching the request.

### Administrator
The project includes an `admin_panel/` directory intended for administrative functionality. User management, reported-account handling, request moderation, and administrative statistics are planned capabilities; their availability depends on the implemented and tested admin functionality.

## 🔄 How the Application Works

1. **Launch:** The user opens BloodConnect and proceeds through the splash and onboarding screens.
2. **Authentication:** The user registers or logs in using email and password.
3. **Role Selection:** The application uses the user's stored role to direct them to the appropriate dashboard.
4. **Donor Registration:** A donor provides profile information, including blood group and city.
5. **Blood Request:** A receiver submits the patient's blood requirements and location.
6. **Donor Discovery:** The application searches for donor profiles matching the required blood group, city, and availability.
7. **Donor Request:** A donor request can be created after validating the blood request and donor information.
8. **Data Storage:** Relevant account, donor, and request information is stored in Cloud Firestore.

**Note:** Donor search results indicate potential matches; they do not guarantee medical compatibility or donor availability at the time of contact.

## 🏗️ System Architecture

BloodConnect follows a client–backend architecture.

```text
              ┌─────────────────────┐
              │   BloodConnect App  │
              │   Flutter + Dart    │
              └──────────┬──────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
     ┌────────▼────────┐   ┌────────▼────────┐
     │ Firebase Auth   │   │ Cloud Firestore │
     │ Login & Signup  │   │ Profiles & Data │
     └─────────────────┘   └─────────────────┘
```

- **Flutter:** Builds the application interface.
- **Firebase Authentication:** Handles user authentication.
- **Cloud Firestore:** Stores user profiles, donor information, blood requests, and related records.
- **Firebase Security Rules:** Define access permissions for supported database operations.

## 🛠️ Technology Stack

| Technology | Purpose |
|---|---|
| Flutter | Cross-platform UI development |
| Dart | Application programming language |
| Firebase Authentication | User authentication |
| Cloud Firestore | Cloud database |
| Firebase CLI | Firebase project management |
| FlutterFire CLI | Flutter and Firebase configuration |
| Git & GitHub | Version control and source code hosting |
| Visual Studio Code | Development environment |

## 🗄️ Database Structure

The project uses the following Firestore collections and supporting Firebase configuration.

| Collection / Resource | Purpose |
|---|---|
| `users` | User accounts, profile information, and roles |
| `donor_profiles` | Donor details, blood group, location, and availability |
| `blood_requests` | Blood requirements submitted by receivers |
| `donor_requests` | Requests connecting donors with blood requests |
| `firestore.rules` | Firestore access-control rules |
| `firestore.indexes.json` | Firestore index configuration |

The exact fields and access permissions depend on the current application implementation and Firebase configuration.

## 📁 Project Structure

```text
blood_connect/
├── android/                 # Android application
├── ios/                     # iOS application
├── web/                     # Web application
├── windows/                 # Windows application
├── linux/                   # Linux application
├── macos/                   # macOS application
├── lib/                     # Main Flutter source code
├── test/                    # Flutter tests
├── admin_panel/             # Administrative project files
├── functions/               # Firebase Functions project
├── push_relay/              # Supporting push-related project files
├── firestore-rules-tests/   # Firestore rules test files
├── firebase.json            # Firebase project configuration
├── firestore.rules          # Firestore security rules
├── firestore.indexes.json   # Firestore indexes
├── storage.rules            # Firebase Storage rules
├── pubspec.yaml             # Flutter dependencies
├── pubspec.lock             # Resolved dependency versions
├── analysis_options.yaml    # Dart analysis configuration
└── README.md                # Project documentation
```

## ⚙️ Installation and Setup

### Prerequisites

Install the following tools before running the project:

- Flutter SDK
- Dart SDK (included with Flutter)
- Visual Studio Code
- Git
- Android Studio for Android SDK and emulator setup
- A Firebase project with the required services configured

### Step 1: Clone the Repository

```bash
git clone https://github.com/YOUR-USERNAME/BloodConnect.git
cd BloodConnect
```

Replace `YOUR-USERNAME` with the actual GitHub username.

### Step 2: Install Dependencies

```bash
flutter pub get
```

### Step 3: Configure Firebase

Configure the application with your own Firebase project.

- Enable Email/Password authentication.
- Create or configure Cloud Firestore.
- Configure the required Firebase platform applications.
- Generate or update `firebase_options.dart` using FlutterFire CLI.
- Apply and test the appropriate Firebase security rules.

Do not commit private service-account credentials, signing keys, passwords, or other secrets to GitHub.

### Step 4: Check the Development Environment

```bash
flutter doctor
```

Resolve any required SDK or platform configuration issues.

### Step 5: Run the Application

```bash
flutter run
```

Select a connected device or configured emulator when prompted.

## 🚧 Current Development Status

BloodConnect is under active development. Authentication, role-based routing, blood request creation, donor discovery, and donor-request validation have been implemented in the project.

Further work and testing are required to confirm the complete end-to-end workflow and finish the remaining features.

## 🔮 Future Improvements

- Complete donor and receiver profile editing.
- Improve donor and receiver dashboards.
- Implement and test complete donor acceptance/rejection workflows.
- Add push notifications for relevant blood requests.
- Complete community features.
- Expand administrative tools and moderation.
- Improve testing, validation, and security.
- Complete Android and iOS release preparation.
- Expand localization and international support.

## 🤝 Contributing

Contributions and suggestions are welcome.

1. Fork the repository.
2. Create a feature branch.
3. Implement and test your changes.
4. Submit a pull request describing the changes.

## 📄 License

A license has not yet been specified. All rights and permissions should be clarified by the project owner before reuse or redistribution.

---

**BloodConnect — Connecting Donors. Supporting Lives.**
