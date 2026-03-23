export const AI_LIMITS = {
  // Active user-facing gating:
  // prompt_limits is the only config that currently blocks prompt submission.
  // The sections below are legacy and do not affect whether a user can keep
  // using chat; they are retained only for backend feature validation and
  // usage/telemetry bookkeeping.
  "prompt_limits": {
    "daily": 50,
    "weekly": 350
  },
  "tiers": {
    "free": {
      "daily_credits": 100,
      "monthly_tokens": 200000
    },
    "pro": {
      "daily_credits": 2000,
      "monthly_tokens": 5000000
    }
  },
  "feature_costs": {
    "ai_chat": 1, // this is the only one used now basically
    "video_editor_chat": 1,
    "ai_project_analysis": 5,
    "ai_mastering": 10,
    "stem_separation": 30
  },
  "token_ratio": {
    "tokens_per_credit": 500
  }
} as const;
