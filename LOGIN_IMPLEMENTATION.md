# UBAA Login Interface Implementation

## Overview

This implementation provides a simple login interface with user information display for the UBAA multi-platform project. The solution follows the modular architecture and supports all target platforms (Android, iOS, Desktop, Web).

## Architecture

### Shared Module (`shared/`)
- **API Layer**: HTTP client with platform-specific implementations
  - `ApiClient.kt`: Multi-platform HTTP client configuration
  - `ApiService.kt`: AuthService and UserService for API calls
  - Platform implementations: Android (OkHttp), iOS (Darwin), JVM (CIO), JS/WASM (JS)

### ComposeApp Module (`composeApp/`)
- **UI Layer**: Compose Multiplatform UI components
  - `AuthViewModel.kt`: State management for authentication flow
  - `LoginScreen.kt`: Login form with username/password input
  - `UserInfoScreen.kt`: User information display with logout
  - `App.kt`: Main application with login/user info navigation

## Features

### Login Screen
- Username/password input fields
- Form validation (non-empty fields)
- Loading state with progress indicator
- Error display with automatic clearing
- Responsive design for different screen sizes

### User Info Screen
- Basic user information (name, school ID)
- Detailed information from API (email, phone, ID card)
- Masked sensitive data (ID card number)
- Logout button to clear session
- Clean card-based layout

### API Integration
- JWT token-based authentication
- Automatic token management in HTTP client
- Error handling with user-friendly messages
- Support for session status checking

## Usage

### Running the Application

1. **Android**: Use the Android run configuration or build APK
2. **Desktop**: Run the JVM target with `./gradlew :composeApp:run`
3. **Web**: Build and serve the JS/WASM target
4. **iOS**: Build through Xcode with the generated framework

### Server Requirements

The application expects a running UBAA server with the following endpoints:
- `POST /api/v1/auth/login` - Login with username/password
- `GET /api/v1/user/info` - Get user information (requires Bearer token)

Server configuration in `Constants.kt`: `SERVER_PORT = 8081`

### Login Process

1. User enters username (school ID) and password
2. Application calls login API and receives JWT token
3. Token is automatically stored in HTTP client for subsequent requests
4. User information is fetched and displayed
5. Logout clears token and returns to login screen

## Testing

The implementation includes unit tests for:
- AuthViewModel state management
- API data models serialization/deserialization
- UI state handling

Run tests with: `./gradlew test`

## Platform Compatibility

The implementation is designed for multi-platform compatibility:

- **Android**: Material Design 3 with proper lifecycle handling
- **iOS**: Native look and feel with iOS-specific HTTP client
- **Desktop**: Desktop window application with proper sizing
- **Web**: Browser-compatible with JS/WASM targets

## Security Considerations

- Passwords are cleared from memory after successful login
- JWT tokens are managed securely by the HTTP client
- Sensitive data (ID card numbers) is masked in the UI
- Session cleanup on logout prevents token leakage

## Error Handling

- Network errors are caught and displayed to users
- Invalid credentials show appropriate error messages
- Loading states prevent multiple concurrent requests
- Automatic error clearing improves user experience