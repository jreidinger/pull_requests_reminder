Pull Requests Reminder
======================

Easy CLI tool to report when there is some long time pending requests in organization

Example for Yast Organization
=============================
Taken from Yast CI node which actually run this Bash script.

```sh
OUTPUT=`ruby pr_reminder.rb yast`
HEADER=$'This email is automatic generated from yast CI node. It lists of pull requests that have no activity more then three working days. If your module is listed, please check all pull request, why they are not merged yet.\n\n'
if [ -n "$OUTPUT" ]; then
  echo "$HEADER$OUTPUT" | mailx -r yast-ci@opensuse.org -s "Pending Pull Requests" yast-devel@opensuse.org
fi
```
