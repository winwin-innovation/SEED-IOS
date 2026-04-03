# Ginx-Seed v1.0

This project now uses a secure backend token flow and includes a native iPhone app under `ios/GinxSeedSwiftUI`:
- Your permanent Decart API key lives only on the backend (`DECART_API_KEY`).
- The frontend requests short-lived client tokens from `POST /api/realtime-token`.

## Requirements

- Node.js 20+ (LTS recommended)
- npm (bundled with Node.js)

## Setup

1. Install dependencies:

```bash
npm install
```

2. Create your `.env` file:

Windows PowerShell:
```powershell
Copy-Item .env.example .env
```

macOS/Linux:
```bash
cp .env.example .env
```

3. Edit `.env` and set your API key:

```env
DECART_API_KEY=your_real_key_here
HOST=0.0.0.0
PORT=8787
```

## Run the app

Start frontend + backend together:

```bash
npm run dev
```

This runs:
- Vite frontend on `http://localhost:5173`
- Backend token server on `http://localhost:8787`

For a physical iPhone, point the SwiftUI app at your computer's LAN IP instead of `localhost`, for example `http://192.168.1.25:8787`.

## Scripts

- `npm run dev`: runs frontend and backend together
- `npm run web`: runs only Vite frontend
- `npm run server`: runs only backend token server
- `npm run preview`: preview static frontend build

## Free iOS build check

This project now includes a GitHub Actions workflow at `.github/workflows/ios-build.yml`.

It does a free cloud build of the native iOS app for the iOS Simulator:
- no Mac required on your side
- no Apple code signing required
- useful for catching Swift/Xcode build errors early

To use it:

1. Create a GitHub repository for this folder.
2. Push the project to `main` or `master`.
3. Open the `Actions` tab on GitHub.
4. Run or inspect the `iOS Build` workflow.

Notes:
- This validates that the SwiftUI app compiles in the cloud.
- It does not produce an App Store build or install directly to your iPhone.
- Later, when you get Mac access, you can use the same project for signing and device testing.

## Share with a friend

When sharing this project:
- Share the codebase and `.env.example`
- Do not share your `.env` file
- Your friend must use their own `DECART_API_KEY`
