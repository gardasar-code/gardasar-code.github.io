# Лендинг Di2 Field (GitHub Pages)

Лендинг живёт в подкаталоге `site/` этого проекта (исходник правды), а на GitHub
публикуется так, что в репозиторий попадает **ТОЛЬКО содержимое `site/`** —
исходники Monkey C, `doc/`, история проекта туда НЕ уходят.

## Как это устроено

GitHub-репозиторий лендинга: `https://github.com/gardasar-code/Di2Field`
(remote называется **`landing`**, не `origin` — чтобы случайный `git push` не
залил туда весь проект).

Публикуем подкаталог `site/` как корень репо через `git subtree`. В корне
GitHub-репо окажется ровно: `index.html`, `icon.svg`, `.nojekyll`.

## Структура `site/`

| Файл | Назначение |
|---|---|
| `site/index.html` | весь лендинг (self-contained: инлайн CSS/JS, Google Fonts) |
| `site/icon.svg` | favicon |
| `site/.nojekyll` | отключает обработку Jekyll (важно для branch-deploy) |

## Публикация (каждый раз после правок лендинга)

1. Закоммить изменения `site/` в этом проекте как обычно.
2. Запушить ТОЛЬКО подкаталог на GitHub:
   ```bash
   git subtree push --prefix=site landing main
   ```
   В корне репо `Di2Field` будет только содержимое `site/`.

> Первый push пустого репо этой же командой создаст ветку `main`.
> Если когда-нибудь история subtree «разойдётся», форсировать так:
> ```bash
> git push landing "$(git subtree split --prefix=site)":main --force
> ```

## Включить Pages (однократно)

GitHub → репозиторий **Di2Field** → **Settings → Pages → Build and deployment →
Source = "Deploy from a branch" → Branch: `main` / `(root)`**.

Через минуту сайт будет на `https://gardasar-code.github.io/Di2Field/`.
(Actions/workflow не нужны — branch-deploy раздаёт корень сам; `.nojekyll`
отключает Jekyll.)

## Заполнить плейсхолдеры

В `site/index.html` помечены `data-todo`:

| Плейсхолдер | На что заменить |
|---|---|
| `STORE_URL` | ссылка на приложение в Connect IQ Store |
| `REPO_URL` | `https://github.com/gardasar-code/Di2Field` |

Поиск: `grep -n "data-todo\|STORE_URL\|REPO_URL" site/index.html`.

## Локальный просмотр

```bash
python3 -m http.server -d site 8080   # http://localhost:8080
```
