# AI-assisted engineering: решения, которые проверены

В этой работе агент использовался для чтения кодовой базы, разработки и запуска проверок. Результаты ниже — наблюдения в showcase, а не доказательство коммерческого стажа пользователя или самостоятельной подготовки к интервью.

| Гипотеза / предложение                                                 | Проверка                                                                       | Итог                                                                                                                                                                     |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Owner read должен ограничивать materialization, сохраняя server search | 50k fanout benchmark; RSpec с timestamp ties, cursor scope и профильным search | 50k → 20 records; точные COUNT остаются дорогими, RSS/production capacity не измерены                                                                                    |
| Failed producer exercise проверяет lost enqueue                        | Первый полный architecture lab                                                 | Не прошёл: здоровый competing dispatcher мог успеть обработать event. Fixture исправлен через остановку только lab dispatcher на фазу outage; новый полный прогон прошёл |
| Узкое исключение Gitleaks можно добавить через inherited targetRules   | Чтение pinned scanner config source, реальный scan и canary                    | Этот вариант не применялся к inherited rule; использовано rule-specific override. Canary в разрешённом report по-прежнему обнаруживается                                 |
| Application audit 0 findings достаточно для image release              | Trivy exact immutable image scan                                               | Недостаточно: найдены runtime OS и npm toolchain CVE; доступные исправления применены, исправления и отдельные patched runtime images закрыли findings; строгий gate теперь проходит. Первые красные scans сохранены                                 |
| Server filter reset завершён к следующему UI click                     | Первый полный browser run                                                      | Один failure. Тест теперь ждёт четыре server-filtered cards; оба owner теста после исправления прошли                                                                    |
| Healthy frontend означает рабочее приложение                           | Diagnostic при остановленном showcase worker                                   | Frontend HTTP 200, но worker/queue probes красные и команда возвращает nonzero                                                                                           |

[Первый lab failure](evidence/showcase-final/lab-attempt-1.json), [успешный lab](evidence/showcase-architecture-lab/summary.json), [secret canary](evidence/showcase-final/gitleaks-canary.json), [image review](security-review.md), [owner recheck](evidence/showcase-final/owner-recheck/playwright.json), [degraded diagnosis](evidence/showcase-final/diagnostic-degraded/diagnostic.json).

Порядок работы: сформулировать инвариант и scope → получить конкретную гипотезу/patch → прочитать diff → запустить проверку, которая может опровергнуть гипотезу → сохранить отрицательный результат → исправить причину → повторить зависимые проверки. Старые failures не превращаются вручную в pass.

На интервью кандидат должен сам объяснить транзакции, SQL, роль runtime, queue guarantees и ограничения restore; перечисление сгенерированных файлов этого не заменяет. Для рассказа о собственном AI опыте нужны реальные примеры пользователя с его личными решениями и проверкой, они ещё не предоставлены.

## Новые опровергнутые предположения

| Гипотеза                                                  | Фактическая проверка                                                                                             | Вывод                                                                                                             |
| --------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Alpine достаточно просто собрать                          | Первый verification stage не имел tzdata; native suite не стартовал                                              | Runtime и verification dependencies согласованы; после исправления 118/118                                        |
| Read-only Grafana сама загрузит нужный datasource         | Runtime auto-update заменял plugin/упирался в readonly path; generic plugin installation потреблял лишнюю память | Нужный официальный Prometheus plugin встроен в image, auto-download отключён; real dashboard browser check прошёл |
| Kubernetes polling увидит terminal DB state после reload  | Первый recovery probe удерживал cached SELECT и считал effects=0, хотя DB уже имела результаты                   | Observation polling использует uncached; первый failure сохранён, новый actual run прошёл                         |
| perform_now обязательно завершил file scan                | Competing dispatcher мог уже забрать claim; файл позже был available                                             | Verification ждёт bounded terminal state и не подменяет scanner outcome                                           |
| Linux shell-helper одинаково стартует из Windows checkout | CRLF приводил к illegal option в Alpine sh                                                                       | LF + .gitattributes; negative release evidence и успешный повтор сохранены                                        |

Эти исправления относятся к проверенным симптомам. Например, факт успешного browser repeat после readiness не доказывает единственную первопричину любых frontend ошибок. Agent outputs оцениваются через проверяемые инварианты и отрицательные результаты, а не уверенность формулировки.

## Проверки последнего повторного запуска

Тестовая среда скрывала проблему настоящих partner callbacks: HTTP 422 из-за browser CSRF. Machine endpoint переведён на stateless API с обязательной raw-body HMAC, replay/sequence protection; browser endpoints сохраняют CSRF. Regression проверяет machine delivery при включённой CSRF protection. CLI drill теперь ждёт три настоящих HTTP 200 receipts.

Повтор demo на тесном host выявил HTTP 500: Errno::ENOMEM в development file watcher при readdir исходников. Interview mode отключает auto-reload и заранее загружает Ruby. [Отрицательные browser/stages отчёты](evidence/publishing-demo-memory-failure/playwright.json) сохранены; исходный API trace наблюдался при диагностике и не включён в этот каталог. Это устраняет наблюдавшийся путь перечитывания, но не обещает неограниченную память или production HA.
