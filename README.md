# robloxcore

Общее ядро фабрики Roblox-игр: экономика, прогрессия, профиль игрока, session-lock,
монетизация, аналитика и процедурный UI. Тайтлы подключают ядро git-сабмодулем
и отличаются только конфигом.

## Слои

| Каталог | Что внутри | Гейт |
|---|---|---|
| `src/logic/` | чистый Luau, ноль Roblox-глобалов | `selene src/logic/` (std = luau) |
| `src/adapters/` | единственное место с `game:GetService` | `selene --config selene-roblox.toml src/adapters` |
| `src/runtime/` | сборка сервисов, зависимости аргументами | то же |
| `src/uikit/` | процедурные экраны | то же |

`logic` не знает про `adapters`, `adapters` знают про `logic`, `runtime` их соединяет.

## Команды

```bash
rokit install
wally install
lune run tests/run.luau
selene src/logic/
selene --config selene-roblox.toml src/adapters src/runtime src/uikit
stylua --check src tests
rojo build -o build.rbxl
```

Тесты — только для `src/logic/`: всё, что трогает Roblox API, проверяется руками
в Studio по чек-листу тайтла.
