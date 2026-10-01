from dataclasses import dataclass, field
import os


@dataclass(frozen=True)
class Settings:
    password: str = field(default="", repr=False)
    data_dir: str = "/data"
    allowed_origins: tuple[str, ...] = ("http://localhost:5173", "http://localhost:4173", "http://localhost:8080", "http://127.0.0.1:5173", "http://127.0.0.1:4173")
    openai_api_key: str = field(default="", repr=False)
    typesafe_api_key: str = field(default="", repr=False)
    openai_model: str = ""
    typesafe_model: str = ""
    elevenlabs_api_key: str = field(default="", repr=False)
    elevenlabs_voice_id: str = ""
    elevenlabs_tts_model: str = "eleven_multilingual_v2"

    @classmethod
    def from_env(cls):
        return cls(
            password=os.environ.get("MIXROOM_PASSWORD", ""),
            data_dir=os.environ.get("MIXROOM_DATA_DIR", "/data"),
            allowed_origins=tuple(s.strip() for s in os.environ.get("MIXROOM_ALLOWED_ORIGINS", ",".join(cls.allowed_origins)).split(",") if s.strip()),
            openai_api_key=os.environ.get("OPENAI_API_KEY", ""), typesafe_api_key=os.environ.get("TYPESAFE_API_KEY", ""),
            openai_model=os.environ.get("OPENAI_MODEL", ""), typesafe_model=os.environ.get("TYPESAFE_MODEL", ""),
            elevenlabs_api_key=os.environ.get("ELEVENLABS_API_KEY", ""), elevenlabs_voice_id=os.environ.get("ELEVENLABS_VOICE_ID", ""),
            elevenlabs_tts_model=os.environ.get("ELEVENLABS_TTS_MODEL", "eleven_multilingual_v2"),
        )

    def validate(self):
        if len(self.password) < 12:
            raise RuntimeError("Set MIXROOM_PASSWORD to at least 12 characters before starting the backend.")
        if any(origin == "*" or origin.endswith("/") or not origin.startswith(("https://", "http://")) for origin in self.allowed_origins):
            raise RuntimeError("MIXROOM_ALLOWED_ORIGINS must contain exact HTTP(S) origins without trailing slashes.")
