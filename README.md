# Workspaces Monorepo

Quick example of a pnpm workspaces monorepo with an `agents` app that consumes an `internal` package. 

## Setup

### Environment

Create a `.env.local` at the root of the project with your LiveKit credentials:
```
LIVEKIT_API_KEY=
LIVEKIT_API_SECRET=
LIVEKIT_URL=
```

### Installation

Install the project dependenices with `pnpm install --frozen-lockfile`.

## Running the agent

Run the agent in the console with:
```
pnpm --filter agent dev
```

## Deploying the agent

Deploy the agent to LiveKit Cloud by running `lk agent create` at the root of the monorepo.