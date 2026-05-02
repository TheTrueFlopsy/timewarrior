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
from basetest.exceptions import CommandError


_ESCAPE_START_CHAR = "\x1b"  # ASCII Escape
_ESCAPE_START_CHAR_2 = "["
_ESCAPE_ARG_CHARS = "0123456789;"
_ESCAPE_END_CHAR = "m"  # end of ANSI "Select Graphic Rendition" escape sequence
_ESCAPE_ARGS_EOR = "0"  # attribute reset, indicating end of attributed range

def _count_wide_chars(s):
    return sum((east_asian_width(c) == "W" for c in s))

# CAUTION: This WON'T be correct when combining diacritics are involved,
# nor in many other cases.
# NOTE: It could be made to give the correct answer more often by inspecting
# each character with category() and/or combining() (to filter out zero-width
# code points).
def _hacked_unicode_width(s):
    return len(s) + _count_wide_chars(s)

def _minutes_to_cols(mins, minutes_per_col):
    rounded_mins = mins
    deviation = mins % minutes_per_col

    # The particular rounding formula used in "helper.cpp:quantizeToNMinutes".
    if deviation < minutes_per_col // 2:
        rounded_mins -= deviation
    else:
        rounded_mins += minutes_per_col - deviation

    return rounded_mins // minutes_per_col

def _get_display_bounds(start_h, start_m, end_h, end_m, minutes_per_col, hour_spacing):
    start_mins = 60*start_h + start_m
    end_mins = 60*end_h + end_m

    start_col = _minutes_to_cols(start_mins, minutes_per_col)

    if end_mins == start_mins:  # special case implemented in "Chart.cpp:renderInterval"
        end_col = _minutes_to_cols(start_mins + 60, minutes_per_col)
    else:
        end_col = _minutes_to_cols(end_mins, minutes_per_col)

    start_col += hour_spacing * (start_mins // 60)
    end_col += hour_spacing * (end_mins // 60)

    return start_col, end_col

def _find_ansi_ranges(s):
    ranges = []
    in_escape = False
    escape_args = None
    in_range = False
    range_start_col = None
    col_i = 0

    for c in s:
        if in_escape:  # inside escape sequence
            if c == _ESCAPE_START_CHAR_2:
                if escape_args is not None:  # should follow _ESCAPE_START_CHAR
                    return None  # fail

                escape_args = ""  # start of escape sequence argument list
            elif c in _ESCAPE_ARG_CHARS:
                if escape_args is None:  # should follow _ESCAPE_START_CHAR_2
                    return None  # fail

                escape_args += c
            elif c == _ESCAPE_END_CHAR:  # end of escape sequence
                if escape_args is None or len(escape_args) == 0:  # should follow escape args
                    return None  # fail

                if in_range:  # inside ANSI attribute range
                    if escape_args != _ESCAPE_ARGS_EOR:  # expecting end of range
                        return None  # fail

                    ranges += ( range_start_col, col_i ),
                    in_range = False
                    range_start_col = None
                else:  # not inside ANSI attribute range
                    if escape_args == _ESCAPE_ARGS_EOR:  # expecting start of range
                        return None  # fail

                    in_range = True
                    range_start_col = col_i

                in_escape = False
                escape_args = None
            else:  # unexpected character in escape sequence
                return None  # fail
        elif c == _ESCAPE_START_CHAR:  # start of escape sequence
            in_escape = True
        else:  # not inside escape sequence
            col_i += _hacked_unicode_width(c)  # Only count columns outside escape sequences.

    return ranges

def _strip_ansi_escapes(s):
    head = ""
    tail = s

    while True:
        # Partition (tail) into (pre_esc, start_of_esc, (esc, end_of_esc, post_esc)).
        pre_esc, sep, tail = tail.partition(_ESCAPE_START_CHAR)
        head += pre_esc  # Add pre_esc to partial stripped string.

        if len(sep) == 0:  # no more escape sequences
            break

        # Partition (tail) into (esc, end_of_esc, post_esc).
        esc, sep, tail = tail.partition(_ESCAPE_END_CHAR)

        if len(sep) == 0:  # end of escape sequence not found
            return None  # fail

    return head


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

    def test_chart_wide_char_tags(self):
        # Identify the positions ((X,Y), zero-based, relative to the start (i.e. UL corner)
        # of the output) of the hours axis and the tracked interval grid.
        # ISSUE: How to robustly determine expected values for these coordinates?
        axis_pos = (11, 1)
        grid_pos = (11, 2)

        # Determine the expected dimensions (width, height) of the tracked interval grid
        # and the surrounding output (e.g. date labels and daily totals).
        # ISSUE: How to robustly determine expected values for these parameters?
        n_days = 7              # all seven days of the week displayed
        lines_per_day = 1       # reports.week.lines=1
        n_hours = 24            # all 24 hours of the day displayed
        minutes_per_col = 15    # reports.week.cell=15
        hour_spacing = 1        # reports.week.spacing=1
        output_extra_width = 7  # width of the totals column ("  HH:MM")

        # Configure our instance of Timewarrior.
        # TODO: Set more Boolean config variables.
        config_settings = [
            ( "reports.week.hours", "no" ),
            ( "reports.week.lines", lines_per_day ),
            ( "reports.week.cell", minutes_per_col ),
            ( "reports.week.spacing", hour_spacing ) ]

        for var, value in config_settings:
            try:
                self.t.config(var, str(value))
            except CommandError as e:
                # NOTE: Suppress CommandErrors due to timew returning non-zero exit status
                # due to an attempt to set a config parameter to its current value. I'm not
                # sure that treating a no-op as an error is a good idea at any layer, TBH.
                pass

        hour_width = max(1, 60//minutes_per_col + hour_spacing)
        day_width = n_hours * hour_width
        grid_dims = (day_width, n_days * lines_per_day)
        output_dims = (grid_pos[0] + grid_dims[0] + output_extra_width, grid_dims[1])

        # Map start and end times of test intervals to start and end columns of
        # corresponding displayed interval blocks.
        interval_bounds = [  # [ ( start_h, start_m, end_h, end_m), ... ]
            ( 4, 0, 7, 30 ),
            ( 8, 0, 11, 0 ),
            ( 11, 0, 15, 30 ),
            ( 15, 30, 17, 0 ) ]

        # [ (start_col, end_col), ... ] # width_in_cols = end_col - start_col
        expected_display_bounds = []  # bounds relative to start of grid row (00:00:00)
        for start_h, start_m, end_h, end_m in interval_bounds:
            expected_display_bounds.append(_get_display_bounds(
                start_h, start_m, end_h, end_m, minutes_per_col, hour_spacing))

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

        # Get "week" reports without and with color.
        nc_code, nc_out, nc_err = self.t("week 2026-02-16 - 2026-02-23 :nocolor")
        c_code, c_out, c_err = self.t("week 2026-02-16 - 2026-02-23 :color")

        # Check the output to determine whether the graph width is equal to the specified width.
        # Look for the right edge of the interval grid in each output line that contains a part of the grid.
        hour_0_col = axis_pos[0]
        hour_23_col = axis_pos[0] + grid_dims[0] - hour_width

        nc_out_lines = nc_out.splitlines()
        c_out_lines = c_out.splitlines()
        self.assertEqual(len(nc_out_lines), len(c_out_lines))
        self.assertTrue(len(nc_out_lines) >= grid_pos[1] + grid_dims[1])

        lineno = 0
        for nc_line, c_line in zip(nc_out_lines, c_out_lines, strict=True):
            # For each c_line, identify the start and end of each displayed interval block
            # by searching for the corresponding ANSI escape sequences. Each interval start should
            # be associated with a "set attributes" sequence (f"\x1b[{attr_args}m"), each interval
            # end with a "reset attributes" sequence ("\x1b[0m"). Verify that this succeeds.
            actual_display_bounds = _find_ansi_ranges(c_line_grid)
            self.assertIsNotNone(actual_display_bounds)
            actual_display_bounds = [
                ( start - grid_pos[0], end - grid_pos[0] ) for start, end in actual_display_bounds ]

            # Strip all ANSI escape sequences from each c_line and nc_line. Verify that this succeeds.
            c_line_stripped = _strip_ansi_escapes(c_line)
            self.assertIsNotNone(c_line_stripped)
            # NOTE: The :nocolor line must be stripped too, because some escape sequences may be
            # present there too (e.g. because the underline attribute is used for line drawing).
            nc_line_stripped = _strip_ansi_escapes(nc_line)
            self.assertIsNotNone(nc_line_stripped)

            # Check whether the stripped output lines are equal.
            self.assertEqual(c_line_stripped, nc_line_stripped)

            if lineno == axis_pos[1]:
                self.assertEqual(len(nc_line), output_dims[0])
                self.assertEqual(nc_line[hour_0_col:(hour_0_col+2)], "0 ")
                self.assertEqual(nc_line[hour_23_col:(hour_23_col+2)], "23")

            if lineno == grid_pos[1]:  # first line of interval grid (contains wide characters)
                # Check whether the total /Unicode display width/ of the line equals the specified width.
                self.assertEqual(_hacked_unicode_width(nc_line), output_dims[0])

                # Check whether the /length in code points/ of the line equals the specified width minus
                # the total extra Unicode display width (i.e. the number of wide (two-column) characters).
                self.assertEqual(len(nc_line), output_dims[0] - _count_wide_chars(nc_line))

                # Check whether the actual interval boundaries in the output match the expected
                # ones in expected_display_bounds.
                self.assertEqual(actual_display_bounds, expected_display_bounds)

                self.assertEqual(nc_line[-3], ":")  # the colon in the daily total
            elif grid_pos[1] < lineno < grid_pos[1] + grid_dims[1]:  # other line (no wide characters)
                self.assertEqual(len(nc_line), output_dims[0])
                self.assertEqual(nc_line[-3], ":")  # the colon in the daily total

            lineno += 1

if __name__ == "__main__":
    from simpletap import TAPTestRunner

    unittest.main(testRunner=TAPTestRunner())
