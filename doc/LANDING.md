# Лендинг Di2 Field (GitHub Pages)

Изолированный статический лендинг. Публикуется на GitHub Pages так, что в сайт
попадает **только** папка `site/` — исходники Monkey C, `doc/`, логи и прочее
в публикацию НЕ уходят.

## Структура

| Путь | Назначение |
|---|---|
| `site/index.html` | весь лендинг (self-contained: инлайн CSS/JS, шрифты с Google Fonts) |
| `site/icon.svg` | favicon |
| `site/.nojekyll` | отключает обработку Jekyll |
| `.github/workflows/pages.yml` | деплой: `upload-pages-artifact` с `path: site` → публикуется только `site/` |

## Как опубликовать (однократно)

1. Создать репозиторий на GitHub и запушить (remote пока не настроен):
   ```bash
   git remote add origin git@github.com:<USER>/<REPO>.git
   git push -u origin main
   ```
2. На GitHub: **Settings → Pages → Build and deployment → Source = "GitHub Actions"**.
3. Любой push в `main`, меняющий `site/**`, задеплоит лендинг. URL появится в
   логе workflow и в Settings → Pages (вида `https://<USER>.github.io/<REPO>/`).

## Заполнить плейсхолдеры

В `site/index.html` помечены атрибутом `data-todo`. Найти и заменить:

| Плейсхолдер | На что заменить |
|---|---|
| `STORE_URL` | ссылка на публичную страницу приложения в Connect IQ Store |
| `REPO_URL` | URL репозитория на GitHub |

Быстрый поиск: `grep -n "data-todo\|STORE_URL\|REPO_URL" site/index.html`.

## Дизайн

Тёмная «приборная» эстетика велокомпьютера: почти чёрный фон с сеткой,
сигнальный лайм-акцент, моноширинные подписи (JetBrains Mono) + Archivo для
заголовков. Герой — живая CSS-реплика дата-поля (бегущая передача по кассете,
пульсирующая точка связи, разряд батареи). Цвета точек связи совпадают с
приложением (blue/yellow/green/navy/orange).

## Локальный просмотр

```bash
open site/index.html          # или любой статический сервер
python3 -m http.server -d site 8080   # http://localhost:8080
```
