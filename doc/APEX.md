# Персональная страница apex (GitHub Pages, корневой user-сайт)

Личная страница `Sergey Lapshin` живёт в подкаталоге `.apex/` этого проекта
(исходник правды), а на GitHub публикуется так, что в репозиторий попадает
**ТОЛЬКО содержимое `.apex/`** — исходники Monkey C, `doc/`, история проекта
туда НЕ уходят. Та же модель, что и у лендинга (`doc/LANDING.md`), но
отдельный repo/remote.

## Как это устроено

GitHub-репозиторий: `https://github.com/gardasar-code/gardasar-code.github.io`
(remote называется **`apex`**, не `origin` — чтобы случайный `git push` не залил
туда весь проект).

Имя репо `gardasar-code.github.io` = **корневой user-сайт**: отдаётся на
`https://gardasar-code.github.io/` (без подпути, в отличие от лендинга
`/Di2Field/`). Это совпадает с `<link rel="canonical">` в `.apex/index.html`.

Публикуем подкаталог `.apex/` как корень репо через `git subtree`.

## Структура `.apex/`

| Файл | Назначение |
|---|---|
| `.apex/index.html` | вся страница (self-contained: инлайн CSS, без зависимостей) |
| `.apex/robots.txt` | директивы индексации |
| `.apex/sitemap.xml` | карта сайта |
| `.apex/yandex_e7f43b5ac814e6c0.html` | верификация Yandex Webmaster |
| `.apex/.nojekyll` | отключает обработку Jekyll (важно для branch-deploy) |

## Публикация (каждый раз после правок страницы)

1. Закоммить изменения `.apex/` в этом проекте как обычно.
2. Запушить ТОЛЬКО подкаталог на GitHub:
   ```bash
   git subtree push --prefix=.apex apex main
   ```
   В корне репо `gardasar-code.github.io` будет только содержимое `.apex/`.

> Если история subtree «разойдётся» (push отклонён как non-fast-forward),
> форсировать так:
> ```bash
> git push apex "$(git subtree split --prefix=.apex)":main --force
> ```

## Включить Pages (однократно)

GitHub → репозиторий **gardasar-code.github.io** → **Settings → Pages → Build and
deployment → Source = "Deploy from a branch" → Branch: `main` / `(root)`**.

Через минуту сайт будет на `https://gardasar-code.github.io/`.
(Actions/workflow не нужны — branch-deploy раздаёт корень сам; `.nojekyll`
отключает Jekyll.)

## Локальный просмотр

```bash
python3 -m http.server -d .apex 8080   # http://localhost:8080
```
