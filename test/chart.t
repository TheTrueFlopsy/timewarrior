#!/usr/bin/env python3

###############################################################################
#
# Copyright 2017 - 2019, Thomas Lauf, Paul Beckingham, Federico Hernandez.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# https://opensource.org/license/mit
#
###############################################################################

import os
import sys
import unittest
from datetime import datetime, timedelta
from unicodedata import east_asian_width

# Ensure python finds the local simpletap module
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from basetest import Timew, TestCase

def count_wide_chars(s):
    return sum((east_asian_width(c) == 'W' for c in s))

# CAUTION: This WON'T be correct when combining diacritics are involved,
# nor in many other cases.
# NOTE: It could be made to give the correct answer more often by inspecting
# each character with category() and/or combining() (to filter out zero-width
# code points).
def hacked_unicode_width(s):
    return len(s) + count_wide_chars(s)

class TestChart(TestCase):
    def setUp(self):
        """Executed before each test in the class"""
        self.t = Timew()

    def test_empty(self):
        """Chart should print warning if no data in range"""
        code, out, err = self.t("day")
        self.assertIn("No filtered data found in the range", out)

    def test_empty_with_exclusions(self):
        """Chart should print warning if no data in range and exclusions and time specified"""
        self.t.config("exclusions.days.monday", "off")
        self.t.config("exclusions.days.tuesday", "off")
        self.t.config("exclusions.days.wednesday", "off")
        self.t.config("exclusions.days.thursday", "off")
        self.t.config("exclusions.days.friday", "off")
        self.t.config("exclusions.days.saturday", "off")
        self.t.config("exclusions.days.sunday", "off")

        now = datetime.now()
        three_hours_before = now - timedelta(hours=3)

        code, out, err = self.t("day {:%H:%M:%S}".format(three_hours_before.time()))

        self.assertIn("No filtered data found in the range", out)

    def test_chart_day_with_invalid_config_for_lines(self):
        """Chart should report error on invalid value for 'reports.day.lines'"""
        self.t("track for 1h")
        code, out, err = self.t.runError("day rc.reports.day.lines=foobar")

        self.assertIn("Invalid integer value for 'reports.day.lines': 'foobar'", err)

    def test_chart_day_with_invalid_config_for_cell(self):
        """Chart should report error on invalid value for 'reports.day.cell'"""
        self.t("track for 1h")
        code, out, err = self.t.runError("day rc.reports.day.cell=foobar")

        self.assertIn("Invalid integer value for 'reports.day.cell': 'foobar'", err)

    def test_chart_week_with_invalid_config_for_lines(self):
        """Chart should report error on invalid value for 'reports.week.lines'"""
        self.t("track for 1h")
        code, out, err = self.t.runError("week rc.reports.week.lines=foobar")

        self.assertIn("Invalid integer value for 'reports.week.lines': 'foobar'", err)

    def test_chart_week_with_invalid_config_for_cell(self):
        """Chart should report error on invalid value for 'reports.week.cell'"""
        self.t("track for 1h")
        code, out, err = self.t.runError("week rc.reports.week.cell=foobar")

        self.assertIn("Invalid integer value for 'reports.week.cell': 'foobar'", err)

    def test_chart_month_with_invalid_config_for_lines(self):
        """Chart should report error on invalid value for 'reports.month.lines'"""
        self.t("track for 1h")
        code, out, err = self.t.runError("month rc.reports.month.lines=foobar")

        self.assertIn("Invalid integer value for 'reports.month.lines': 'foobar'", err)

    def test_chart_month_with_invalid_config_for_cell(self):
        """Chart should report error on invalid value for 'reports.month.cell'"""
        self.t("track for 1h")
        code, out, err = self.t.runError("month rc.reports.month.cell=foobar")

        self.assertIn("Invalid integer value for 'reports.month.cell': 'foobar'", err)

    def test_chart_day_with_less_than_one_minute_interval_at_day_start(self):
        self.t("track 2016-01-15T00:00:00 - 2016-01-15T00:00:40 XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO")
        code, out, err = self.t("day 2016-01-15 - 2016-01-16")

        self.assertIn("""\
\nFri 15 XOXO 1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20   21   22   23   \
\n       XOXO                                                                                                                    \
\n
       Tracked         0:00:40
       Available      23:59:20
       Total          24:00:00

""", out)

    def test_chart_day_with_less_than_one_minute_interval(self):
        self.t(
            "track 2016-01-15T02:00:00 - 2016-01-15T02:00:40 XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO")
        code, out, err = self.t("day 2016-01-15 - 2016-01-16")

        self.assertIn("""\
\nFri 15 0    1    XOXO 3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20   21   22   23   \
\n                 XOXO                                                                                                          \
\n
       Tracked         0:00:40
       Available      23:59:20
       Total          24:00:00

""", out)

    def test_chart_day_with_less_than_one_hour_interval_at_day_start(self):
        self.t(
            "track 2016-01-15T00:00:00 - 2016-01-15T00:30:00 XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO")
        code, out, err = self.t("day 2016-01-15 - 2016-01-16")

        self.assertIn("""\
\nFri 15 XO   1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20   21   22   23   \
\n       XO                                                                                                                      \
\n
       Tracked         0:30:00
       Available      23:30:00
       Total          24:00:00

""", out)

    def test_chart_day_with_less_than_one_hour_interval(self):
        self.t(
            "track 2016-01-15T02:00:00 - 2016-01-15T02:30:00 XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO")
        code, out, err = self.t("day 2016-01-15 - 2016-01-16")

        self.assertIn("""\
\nFri 15 0    1    XO   3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20   21   22   23   \
\n                 XO                                                                                                            \
\n
       Tracked         0:30:00
       Available      23:30:00
       Total          24:00:00

""", out)

    def test_chart_day_with_interval_over_day_border(self):
        self.t("track 2016-01-15T23:00:00 - 2016-01-16T01:00:00 XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO")
        code, out, err = self.t("day 2016-01-15 - 2016-01-17")

        self.assertIn("""\
\nFri 15 0    1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20   21   22   XOXOX\
\n                                                                                                                          OXOXO\
\nSat 16 XOXOX1    2    3    4    5    6    7    8    9    10   11   12   13   14   15   16   17   18   19   20   21   22   23   \
\n       OXOXO                                                                                                                   \
\n
       Tracked         2:00:00
       Available      46:00:00
       Total          48:00:00

""", out)

    def test_chart_day_with_interval_over_whole_day(self):
        self.t("track 2016-01-15T00:00:00 - 2016-01-16T00:00:00 XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO")
        code, out, err = self.t("day 2016-01-15 - 2016-01-16")

        self.assertIn("""\
\nFri 15 XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO\
\n       XOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXOXO\
\n
       Tracked        24:00:00
       Available       0:00:00
       Total          24:00:00

""", out)

    def test_chart_wide_char_tags_nocolor(self):
        # Identify the positions ((X,Y), zero-based, relative to the start (i.e. UL corner) of the output)
        # of the hours axis and the tracked interval grid.
        # ISSUE: How to robustly determine expected values for these coordinates?
        axis_pos = (11, 1)
        grid_pos = (11, 2)

        # Determine the expected dimensions (width, height) of the tracked interval grid
        # and the surrounding output (e.g. date labels and daily totals).
        # ISSUE: How to robustly determine expected values for these parameters?
        n_days = 7              # all seven days of the week displayed
        lines_per_day = 1       # reports.week.lines=1
        n_hours = 24            # all 24 hours of the day displayed
        minutes_per_char = 15   # reports.week.cell=15
        hour_spacing = 1        # reports.week.spacing=1
        output_extra_width = 7  # width of the totals column ("  HH:MM")

        hour_width = max(1, 60//minutes_per_char + hour_spacing)
        day_width = n_hours * hour_width
        grid_dims = (day_width, n_days * lines_per_day)
        output_dims = (grid_pos[0] + grid_dims[0] + output_extra_width, grid_dims[1])

        # Track some itervals to have something to work with. Use tag names that include wide characters.
        # NOTE: The Timew class uses the standard 'shlex' module for shell-compatible splitting of the
        # argument string (e.g. parsing 'herpa derpa ding dong' as a single argument).
        self.t("track 2026-02-16T04:00:00 - 2026-02-16T07:30:00 😍tag_test😍")
        self.t("track 2026-02-16T08:00:00 - 2026-02-16T11:00:00 测试测试")
        self.t("track 2026-02-16T11:00:00 - 2026-02-16T15:30:00 SãoSebastião")
        self.t("track 2026-02-16T15:30:00 - 2026-02-16T17:00:00 'herpa derpa ding dong'")

        # NOTE: Track some time each day of the week to ensure that all lines of the interval grid
        # are full-width (with a daily total in the totals column).
        self.t("track 2026-02-17T00:00:00 - 2026-02-17T03:00:00 'herpa derpa ding dong'")
        self.t("track 2026-02-18T03:00:00 - 2026-02-18T06:00:00 'herpa derpa ding dong'")
        self.t("track 2026-02-19T06:00:00 - 2026-02-19T09:00:00 'herpa derpa ding dong'")
        self.t("track 2026-02-20T09:00:00 - 2026-02-20T12:00:00 'herpa derpa ding dong'")
        self.t("track 2026-02-21T12:00:00 - 2026-02-21T15:00:00 'herpa derpa ding dong'")
        self.t("track 2026-02-22T15:00:00 - 2026-02-22T18:00:00 'herpa derpa ding dong'")

        # Get a "week" report.
        code, out, err = self.t("week 2026-02-16 - 2026-02-23 :nocolor")

        # Check the output to determine whether the graph width is equal to the specified width.
        # Look for the right edge of the interval grid in each output line that contains a part of the grid.
        hour_0_col = axis_pos[0]
        hour_23_col = axis_pos[0] + grid_dims[0] - hour_width

        out_lines = out.splitlines()
        self.assertTrue(len(out_lines) >= grid_pos[1] + grid_dims[1])

        lineno = 0
        for line in out_lines:
            if lineno == axis_pos[1]:
                self.assertEqual(len(line), output_dims[0])
                self.assertEqual(line[hour_0_col:(hour_0_col+2)], '0 ')
                self.assertEqual(line[hour_23_col:(hour_23_col+2)], '23')

            if lineno == grid_pos[1]:  # first line of interval grid (contains wide characters)
                # Check whether the total /Unicode display width/ of the line equals the specified width.
                self.assertEqual(hacked_unicode_width(line), output_dims[0])

                # Check whether the /length in code points/ of the line equals the specified width minus
                # the total extra Unicode display width (i.e. the number of wide (two-column) characters).
                self.assertEqual(len(line), output_dims[0] - count_wide_chars(line))

                self.assertEqual(line[-3], ':')  # the colon in the daily total
            elif grid_pos[1] < lineno < grid_pos[1] + grid_dims[1]:  # other line (no wide characters)
                self.assertEqual(len(line), output_dims[0])
                self.assertEqual(line[-3], ':')  # the colon in the daily total

            lineno += 1

    def test_chart_wide_char_tags_color(self):
        pass  # TODO: Implement this.

if __name__ == "__main__":
    from simpletap import TAPTestRunner

    unittest.main(testRunner=TAPTestRunner())
