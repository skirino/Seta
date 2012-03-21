/*
Copyright (C) 2012 Shunsuke Kirino <shunsuke.kirino@gmail.com>

This file is part of Seta.
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3, or (at your option)
any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this software; see the file GPL. If not, contact the
Free Software Foundation, 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301 USA.
*/

module utils.time_util;

import core.stdc.time;
import core.sys.posix.sys.time;
import std.stdio;


scope class ScopeTimer
{
private:
  timeval start_;
  const string message_;

public:
  this(string message)
  {
    message_ = message;
    gettimeofday(&start_, null);
  }

  ~this()
  {
    timeval end;
    gettimeofday(&end, null);
    if (end.tv_usec < start_.tv_usec){
      writefln(
        "%d seconds + %d microseconds elapsed : %s",
        end.tv_sec - start_.tv_sec - 1,
        1000000 + end.tv_usec - start_.tv_usec,
        message_);
    }
    else {
      writefln(
        "%d seconds + %d microseconds elapsed : %s",
        end.tv_sec - start_.tv_sec,
        end.tv_usec - start_.tv_usec,
        message_);
    }
  }
}


ulong GetCurrentTime()
{
  return time(null);
}


string EpochTimeToString(ulong l)
{
  char[16] ret;

  tm st;
  auto t = cast(time_t) l;
  core.sys.posix.time.localtime_r(&t, &st);

  // 1900 + st.tm_year represents the year
  ret[0..4] = YEAR_1900_TO_2100[st.tm_year].dup;
  ret[4] = '-';
  ret[5..7] = ZERO_TO_61[st.tm_mon+1].dup;
  ret[7] = '/';
  ret[8..10] = ZERO_TO_61[st.tm_mday].dup;
  ret[10] = ' ';
  ret[11..13] = ZERO_TO_61[st.tm_hour].dup;
  ret[13] = ':';
  ret[14..16] = ZERO_TO_61[st.tm_min].dup;

  return ret[].idup;// return slice of local buffer
}

string EpochTimeToStringSeconds(ulong l)
{
  char[14] ret;

  tm st;
  auto t = cast(time_t) l;
  core.sys.posix.time.localtime_r(&t, &st);

  ret[0..2] = ZERO_TO_61[st.tm_mon+1].dup;
  ret[2] = '/';
  ret[3..5] = ZERO_TO_61[st.tm_mday].dup;
  ret[5] = ' ';
  ret[6..8] = ZERO_TO_61[st.tm_hour].dup;
  ret[8] = ':';
  ret[9..11] = ZERO_TO_61[st.tm_min].dup;
  ret[11] = ':';
  ret[12..14] = ZERO_TO_61[st.tm_sec].dup;

  return ret[].idup;// return slice of local buffer
}


private static const char[4][201] YEAR_1900_TO_2100 =
  [
    "1900",
    "1901",
    "1902",
    "1903",
    "1904",
    "1905",
    "1906",
    "1907",
    "1908",
    "1909",
    "1910",
    "1911",
    "1912",
    "1913",
    "1914",
    "1915",
    "1916",
    "1917",
    "1918",
    "1919",
    "1920",
    "1921",
    "1922",
    "1923",
    "1924",
    "1925",
    "1926",
    "1927",
    "1928",
    "1929",
    "1930",
    "1931",
    "1932",
    "1933",
    "1934",
    "1935",
    "1936",
    "1937",
    "1938",
    "1939",
    "1940",
    "1941",
    "1942",
    "1943",
    "1944",
    "1945",
    "1946",
    "1947",
    "1948",
    "1949",
    "1950",
    "1951",
    "1952",
    "1953",
    "1954",
    "1955",
    "1956",
    "1957",
    "1958",
    "1959",
    "1960",
    "1961",
    "1962",
    "1963",
    "1964",
    "1965",
    "1966",
    "1967",
    "1968",
    "1969",
    "1970",
    "1971",
    "1972",
    "1973",
    "1974",
    "1975",
    "1976",
    "1977",
    "1978",
    "1979",
    "1980",
    "1981",
    "1982",
    "1983",
    "1984",
    "1985",
    "1986",
    "1987",
    "1988",
    "1989",
    "1990",
    "1991",
    "1992",
    "1993",
    "1994",
    "1995",
    "1996",
    "1997",
    "1998",
    "1999",
    "2000",
    "2001",
    "2002",
    "2003",
    "2004",
    "2005",
    "2006",
    "2007",
    "2008",
    "2009",
    "2010",
    "2011",
    "2012",
    "2013",
    "2014",
    "2015",
    "2016",
    "2017",
    "2018",
    "2019",
    "2020",
    "2021",
    "2022",
    "2023",
    "2024",
    "2025",
    "2026",
    "2027",
    "2028",
    "2029",
    "2030",
    "2031",
    "2032",
    "2033",
    "2034",
    "2035",
    "2036",
    "2037",
    "2038",
    "2039",
    "2040",
    "2041",
    "2042",
    "2043",
    "2044",
    "2045",
    "2046",
    "2047",
    "2048",
    "2049",
    "2050",
    "2051",
    "2052",
    "2053",
    "2054",
    "2055",
    "2056",
    "2057",
    "2058",
    "2059",
    "2060",
    "2061",
    "2062",
    "2063",
    "2064",
    "2065",
    "2066",
    "2067",
    "2068",
    "2069",
    "2070",
    "2071",
    "2072",
    "2073",
    "2074",
    "2075",
    "2076",
    "2077",
    "2078",
    "2079",
    "2080",
    "2081",
    "2082",
    "2083",
    "2084",
    "2085",
    "2086",
    "2087",
    "2088",
    "2089",
    "2090",
    "2091",
    "2092",
    "2093",
    "2094",
    "2095",
    "2096",
    "2097",
    "2098",
    "2099",
    "2100"
    ];

private static const char[2][61] ZERO_TO_61=
  [
    "00",
    "01",
    "02",
    "03",
    "04",
    "05",
    "06",
    "07",
    "08",
    "09",
    "10",
    "11",
    "12",
    "13",
    "14",
    "15",
    "16",
    "17",
    "18",
    "19",
    "20",
    "21",
    "22",
    "23",
    "24",
    "25",
    "26",
    "27",
    "28",
    "29",
    "30",
    "31",
    "32",
    "33",
    "34",
    "35",
    "36",
    "37",
    "38",
    "39",
    "40",
    "41",
    "42",
    "43",
    "44",
    "45",
    "46",
    "47",
    "48",
    "49",
    "50",
    "51",
    "52",
    "53",
    "54",
    "55",
    "56",
    "57",
    "58",
    "59",
    "60"
    ];

