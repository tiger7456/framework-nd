#include "RulesTable.hpp"
#include <string>
#include <map>
#include <vector>
#include <assert.h>
#include <utility>

#include <iostream>

using namespace std;

enum ParseState
{
    PARSE_STATE_NONE = 0,
    PARSE_STATE_METHOD_GET,
    PARSE_STATE_METHOD_POST,
    PARSE_STATE_HOST,
    PARSE_STATE_USER_AGENT,

	//special purpose
    PARSE_STATE_IGNORE_LINE,
	PARSE_STATE_SAVE_TO_END,
	PARSE_STATE_SAVE_TO_BLANK,
    PARSE_STATE_STATE_CNT
};

int main ()
{
    string input = 
        "GET / HTTP/1.1\r\n"
        "Host: mil.news.sina.com.cn\r\n"
        "Connection: keep-alive\r\n"
        "User-Agent: Mozilla/5.0 (Windows NT 5.2) AppleWebKit/535.1 (KHTML, like Gecko) Chrome/14.0.835.202 Safari/535.1\r\n"
        "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n"
        "Accept-Encoding: gzip,deflate,sdch\r\n"
        "Accept-Language: zh-CN,zh;q=0.8\r\n"
        "Accept-Charset: GBK,utf-8;q=0.7,*;q=0.3\r\n"
        "Cookie: U_TRS1=00000034.1eb51011.4e802baa.3ee7a4d7; UOR=www.google.se,tech,; vjuids=-6d518a352.132a8b4272e.0.29523f79; SINAGLOBAL=b73e094c.b80c56c4.4e813499.3a23ae1b; ALLYESID4=00110927124248568603354; mvsign=v%3D2K%5E-dqb%3D0xCCO%3AN%27n6Mm; user_survey=-1; SGUP=0; U_TRS2=000000d3.b986704c.4edec157.79d78b9a; SinaRot//=83; tblogt=0; Apache=000000d3.458528a1.4edef248.f8e543e4; ULV=1323233746111:75:7:4:000000d3.458528a1.4edef248.f8e543e4:1323145903192; StreamMediaCookiehttp://mil.news.sina.com.cn/=1; vjlast=1323233748.1323234260.10; _s_upa=18\r\n"
        "If-Modified-Since: Wed, 07 Dec 2011 04:54:59 GMT\r\n"
        "\r\n"
        "HTTP/1.0 200 OK\r\n"
        "Date: Wed, 07 Dec 2011 06:25:32 GMT\r\n"
        "Server: Apache\r\n"
        "Last-Modified: Wed, 07 Dec 2011 06:24:20 GMT\r\n"
        "Accept-Ranges: bytes\r\n"
        "X-Powered-By: mod_xlayout/rc2\r\n"
        "Cache-Control: max-age=60\r\n"
        "Expires: Wed, 07 Dec 2011 06:26:32 GMT\r\n"
        "Vary: Accept-Encoding\r\n"
        "Content-Encoding: gzip\r\n"
        "X-UA-Compatible: IE=EmulateIE7\r\n"
        "Content-Type: text/html\r\n"
        "X-Cache: MISS from 236-26.D07071946.sina.com.cn\r\n"
        "Connection: close\r\n"
        ;

    typedef std::pair<ParseState, string> HttpHeaderDef;
    typedef std::vector< HttpHeaderDef > HttpHeaderDefs;
    HttpHeaderDefs httpHeaderDefs;
    httpHeaderDefs.push_back(make_pair(PARSE_STATE_USER_AGENT, "User-Agent:")); 
    httpHeaderDefs.push_back(make_pair(PARSE_STATE_METHOD_GET, "GET ")); 
    httpHeaderDefs.push_back(make_pair(PARSE_STATE_METHOD_POST, "POST ")); 

	RulesTable2<char, int, int> rulesTable;
    rulesTable.setDefaultRule(PARSE_STATE_IGNORE_LINE);

    map<string, int> subStates;
    int nextSubState = -1;

    HttpHeaderDefs::iterator it = httpHeaderDefs.begin();
    for (; it != httpHeaderDefs.end(); it++)
    {
        string key = it->second;
        int preState = PARSE_STATE_NONE;
        int curState = PARSE_STATE_NONE;
        for (unsigned i = 1; i < key.length(); i++) 
        {
            string preStr = key.substr(0, i);
            map<string, int>::iterator it = subStates.find(preStr);
            if (it != subStates.end())
            {
                curState = it->second;            
            }
            else
            {
                subStates[preStr] = nextSubState;
                curState = nextSubState;
                nextSubState--;
            }
            rulesTable.setRule(key.at(i-1), preState, curState);
            preState = curState;
        }
        rulesTable.setRule(key.at(key.length()-1), preState, it->first);
    }


    {
        int state = PARSE_STATE_NONE;
		int saveStart = -1;
		int keyId = PARSE_STATE_NONE;
        for (unsigned i = 0; i < input.length(); i++)
        {
            char ch = input[i];
			if ('\n' == ch)
			{
				state = PARSE_STATE_NONE;
				saveStart = -1;
				continue;
			}

            if (PARSE_STATE_IGNORE_LINE == state) 
            {
				continue;
            }
			if (PARSE_STATE_SAVE_TO_END == state)
			{
				if (' ' == ch && saveStart == (int)i)
				{
					saveStart = i + 1;
					continue;
				}
                else if ('\r' == ch)
                {
					assert(saveStart != -1);
					std::cout << "key id:" << keyId << ", out:" << input.substr(saveStart, i - saveStart) << endl;
					state = PARSE_STATE_IGNORE_LINE;
                    continue;
                }
                else
                {
                    continue;
                }

			}
			if (PARSE_STATE_SAVE_TO_BLANK == state)
			{
				if (' ' == ch && saveStart == (int)i)
				{
					saveStart = i + 1;
					continue;
				}
				else if (' ' == ch)
				{
					assert(saveStart != -1);
					std::cout << "key id:" << keyId << ", out:" << input.substr(saveStart, i - saveStart) << endl;
					state = PARSE_STATE_IGNORE_LINE;
                    continue;
				}
				else
				{
					continue;
				}
			}

			state = rulesTable.getRule(ch, state);
			if (PARSE_STATE_USER_AGENT == state)
			{
				keyId = PARSE_STATE_USER_AGENT;
				state = PARSE_STATE_SAVE_TO_END;
				saveStart = i + 1;
				continue;
			}
            else if (PARSE_STATE_METHOD_GET == state)
            {
                keyId = PARSE_STATE_METHOD_GET;
                state = PARSE_STATE_SAVE_TO_BLANK;
				saveStart = i + 1;
				continue;
            }

        }
    }

    return 0;
}

