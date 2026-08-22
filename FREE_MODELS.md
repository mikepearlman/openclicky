# Free models with this fork

This fork adds friendly env vars so you don't need a Claude subscription.

All config lives in `~/.config/openclicky/secrets.env` (or Xcode scheme environment).

### OpenRouter (free vision models)
```env
OPENROUTER_API_KEY=sk-or-v1-xxx
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
```
Pick a free vision model in the app's model picker (e.g. `qwen/qwen2.5-vl-...:free`). Needs vision for the click-and-point to work.

### LM Studio (local, offline)
Start LM Studio → Developer → Start Server on `http://localhost:1234`, load a vision model like `qwen2-vl` or `llava`.
```env
OPENAI_BASE_URL=http://localhost:1234/v1
OPENAI_API_KEY=lm-studio
```

### grok.build
```env
GROK_API_KEY=your-key
GROK_BASE_URL=https://api.grok.build/v1
```

### Any OpenAI-compatible
```env
LLM_API_KEY=your-key
LLM_BASE_URL=https://your-provider/v1
```

You can also still use the original names `ANTHROPIC_API_KEY` / `ANTHROPIC_BASE_URL` and `OPENAI_API_KEY` / `OPENAI_BASE_URL` — they're all aliases now.
