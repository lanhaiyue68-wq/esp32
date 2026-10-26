# Validation guide

1. Dispatch ipa.yml on codex/fix-logs32-task-execution; inspect the exact run SHA and complete results.
2. Confirm all Logs36RegressionTests, general input and learning visibility tests pass along with the full old suite.
3. In the signed build75, open Home > Learning and Settings > Learning. Old lessons, if any, must display with their true sources; an empty store must not show example learning.
4. Run a task, then inspect its recent learning status. An eligible review may add up to three real lessons; skipped/failed reviews must say why without inventing lessons.
5. Run a similar task twice; inspect actual reference counters and last source run/task, then restart the app and check persistence.
6. Disable a lesson, run a similar task and inspect its request trace; it must not be included. Deletion must persist. A clear during a pending review must remain cleared.
7. Test text entry beyond a greeting: long Chinese, English, multiline code, kana/Arabic/emoji where the target allows paste. Compare the exact field before sending. The wireless board remains connected; no USB.
8. Phone tests require the user's hardware. Compilation, simulator and file checks do not establish end-to-end physical tapping accuracy.
