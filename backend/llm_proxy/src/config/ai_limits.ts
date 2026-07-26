export const AI_LIMITS = {
  // Active user-facing gating:
  // prompt_limits is the only config that currently blocks prompt submission.
  // The sections below are legacy and do not affect whether a user can keep
  // using chat; they are retained only for backend feature validation and
  // usage/telemetry bookkeeping.
  "prompt_limits": {
    "free": {
      "daily": 200,
      "weekly": 600
    },
    "starter": {
      "daily": 400,
      "weekly": 1500
    },
    "producer": {
      "daily": 1000,
      "weekly": 4000
    },
    "studio": {
      "daily": 1000,
      "weekly": 4000
    },
    "enterprise": {
      "daily": 1000,
      "weekly": 4000
    },
    "education": {
      "daily": 400,
      "weekly": 1500
    }
  },
  "tiers": {
    "free": {
      "daily_credits": 100,
      "monthly_tokens": 200000
    },
    "starter": {
      "daily_credits": 1000,
      "monthly_tokens": 2500000
    },
    "producer": {
      "daily_credits": 2000,
      "monthly_tokens": 5000000
    },
    "studio": {
      "daily_credits": 10000,
      "monthly_tokens": 25000000
    }
  },
  "feature_costs": {
    "ai_chat": 1, // this is the only one used now basically
    "ai_chat_v3": 1,
    "video_editor_chat": 1,
    "ai_project_analysis": 5,
    "ai_mastering": 10,
    "stem_separation": 30
  },
  "token_ratio": {
    "tokens_per_credit": 500
  }
} as const;
