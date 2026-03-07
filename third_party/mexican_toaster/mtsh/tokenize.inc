// Tokenizer and parser state machine
static char *Tokenize(void) {
  int c, t, rc;
  for (t = STATE_WHITESPACE;; ++p) {
    switch (t) {

      case STATE_WHITESPACE:
        if (!*p)
          return 0;
        if (*p == ' ' || *p == '\t' || *p == '\n' ||
            (p[0] == '\\' && p[1] == '\n')) {
          continue;
        }
        t = STATE_CMD;
        // fallthrough

      case STATE_CMD:
        if (unsupported[*p & 255]) {
          UnsupportedSyntax(*p);
        }
        if (!*p || *p == ' ' || *p == '\t') {
          return Finish();
        } else if (*p == '#') {
          if (q > r) {
            return Finish();
          }
          // Skip to end of line or end of string
          while (*p && *p != '\n') ++p;
          // If we hit a newline, back up one so the loop increment moves us to it
          if (*p == '\n') --p;
          // If we hit end of string, we're done with this command
          if (!*p) return 0;
          continue;
        } else if (*p == '"') {
          t = STATE_QUOTED;
        } else if (*p == '\'') {
          t = STATE_SINGLE;
        } else if (*p == '`') {
          // Backtick command substitution: `command`
          char *end = strchr(p + 1, '`');
          if (!end) {
            tinyprint(2, prog, ": unmatched '`'\n", NULL);
            _Exit(15);
          }
          size_t len = end - (p + 1);
          if (len >= 4096) {
            tinyprint(2, prog, ": command substitution too long\n", NULL);
            _Exit(12);
          }
          static char backcmd[4096];
          memcpy(backcmd, p + 1, len);
          backcmd[len] = 0;
          CaptureCommand(backcmd, 0);  // unquoted context
          p = end;
        } else if (*p == '$' && p[1] == '(') {
          // $() command substitution: $(command)
          char *end = strchr(p + 2, ')');
          if (!end) {
            tinyprint(2, prog, ": unmatched '$('\n", NULL);
            _Exit(15);
          }
          size_t len = end - (p + 2);
          if (len >= 4096) {
            tinyprint(2, prog, ": command substitution too long\n", NULL);
            _Exit(12);
          }
          static char dollarcmd[4096];
          memcpy(dollarcmd, p + 2, len);
          dollarcmd[len] = 0;
          CaptureCommand(dollarcmd, 0);  // unquoted context
          p = end;
        } else if (*p == '$') {
          t = STATE_VAR;
          var[(vari = 0)] = 0;
        } else if (*p == '\\') {
          if (!p[1])
            UnsupportedSyntax(*p);
          Append(*++p);
        } else if (*p == '=') {
          if (!n && q > r)
            assign = r;
          Append(*p);
        } else if (*p == '(') {
          // Subshell grouping: (command)
          if (q > r) {
            return Finish();
          }
          // Find matching )
          char *start = p + 1;
          char *end = start;
          int depth = 1;
          while (*end && depth > 0) {
            if (*end == '(') depth++;
            if (*end == ')') depth--;
            if (depth > 0) end++;
          }
          if (depth != 0) {
            tinyprint(2, prog, ": unmatched '('\n", NULL);
            _Exit(15);
          }
          // Extract and execute substring
          size_t len = end - start;
          if (len >= 4096) {
            tinyprint(2, prog, ": subshell command too long\n", NULL);
            _Exit(12);
          }
          static char subcmd[4096];
          memcpy(subcmd, start, len);
          subcmd[len] = 0;
          // Execute in subshell
          exitstatus = ExecuteSubshell(subcmd);
          p = end;
          t = STATE_WHITESPACE;
        } else if (*p == ')') {
          tinyprint(2, prog, ": unmatched ')'\n", NULL);
          _Exit(15);
        } else if (*p == '|') {
          if (q > r) {
            return Finish();
          } else if (p[1] == '|') {
            rc = ShellSpawn();
            if (!rc) {
              // Success: skip to &&, ;, or end
              ++p;  // skip second |
              while (*p && *p != ';' && *p != '\n' && !(*p == '&' && p[1] == '&')) {
                if (*p == '(') {
                  // Skip subshell
                  int depth = 1;
                  ++p;
                  while (*p && depth > 0) {
                    if (*p == '(') depth++;
                    if (*p == ')') depth--;
                    ++p;
                  }
                  if (depth == 0) --p;
                } else {
                  ++p;
                }
              }
              // If we hit &&, continue evaluating (don't exit)
              // If we hit ; or end, exit with success
              if (!*p || *p == ';' || *p == '\n') {
                _Exit(0);
              }
              t = STATE_WHITESPACE;
            } else {
              // Failure: continue to next command
              ++p;
              t = STATE_WHITESPACE;
            }
          } else {
            Pipe();
            t = STATE_WHITESPACE;
          }
        } else if (*p == ';' || *p == '\n') {
          if (q > r) {
            return Finish();
          } else {
            exitstatus = ShellSpawn();
            t = STATE_WHITESPACE;
          }
        } else if (*p == '>') {
          Append(*p);
          if (p[1] == '&') {
            Append(*++p);
          }
        } else if (*p == '&') {
          if (q > r) {
            return Finish();
          } else if (p[1] == '&') {
            rc = ShellSpawn();
            if (!rc) {
              // Success: continue to next command
              ++p;
              t = STATE_WHITESPACE;
            } else {
              // Failure: skip to || or ; or end
              ++p;  // skip second &
              while (*p && *p != ';' && *p != '\n' && !(*p == '|' && p[1] == '|')) {
                if (*p == '(') {
                  // Skip subshell
                  int depth = 1;
                  ++p;
                  while (*p && depth > 0) {
                    if (*p == '(') depth++;
                    if (*p == ')') depth--;
                    ++p;
                  }
                  if (depth == 0) --p;  // back up to the )
                } else {
                  ++p;
                }
              }
              if (*p == '|' && p[1] == '|') {
                ++p;  // will be incremented again by loop, landing after ||
              } else if (*p == ';' || *p == '\n' || !*p) {
                // Command chain ended with failure
                _Exit(rc);
              }
              t = STATE_WHITESPACE;
            }
          } else {
            ShellSpawnAsync();
            t = STATE_WHITESPACE;
          }
        } else {
          Append(*p);
        }
        break;

      case STATE_VAR:
        // XXX: we need to find a simple elegant way to break up
        //      unquoted variable expansions into multiple args.
        if (CopyVar())
          t = STATE_CMD, --p;
        break;

      case STATE_SINGLE:
        if (!*p)
          goto UnterminatedString;
        if (*p == '\'') {
          t = STATE_CMD;
        } else {
          Append(*p);
        }
        break;

      UnterminatedString:
        tinyprint(2, "cmd: error: unterminated string\n", NULL);
        _Exit(6);

      case STATE_QUOTED_VAR:
        if (!*p)
          goto UnterminatedString;
        if (CopyVar())
          t = STATE_QUOTED, --p;
        break;

      case STATE_QUOTED:
        if (!*p)
          goto UnterminatedString;
        if (*p == '"') {
          t = STATE_CMD;
        } else if (*p == '`') {
          // Backtick command substitution in quotes
          char *end = strchr(p + 1, '`');
          if (!end) {
            tinyprint(2, prog, ": unmatched '`'\n", NULL);
            _Exit(15);
          }
          size_t len = end - (p + 1);
          if (len >= 4096) {
            tinyprint(2, prog, ": command substitution too long\n", NULL);
            _Exit(12);
          }
          static char qbackcmd[4096];
          memcpy(qbackcmd, p + 1, len);
          qbackcmd[len] = 0;
          CaptureCommand(qbackcmd, 1);  // quoted context
          p = end;
        } else if (p[0] == '$' && p[1] == '(') {
          // $() command substitution in quotes
          char *end = strchr(p + 2, ')');
          if (!end) {
            tinyprint(2, prog, ": unmatched '$('\n", NULL);
            _Exit(15);
          }
          size_t len = end - (p + 2);
          if (len >= 4096) {
            tinyprint(2, prog, ": command substitution too long\n", NULL);
            _Exit(12);
          }
          static char qdollarcmd[4096];
          memcpy(qdollarcmd, p + 2, len);
          qdollarcmd[len] = 0;
          CaptureCommand(qdollarcmd, 1);  // quoted context
          p = end;
        } else if (p[0] == '$') {
          t = STATE_QUOTED_VAR;
          var[(vari = 0)] = 0;
        } else if (p[0] == '\\') {
          switch ((c = *++p)) {
            case 0:
              UnsupportedSyntax('\\');
            case '\n':
              break;
            case '$':
            case '`':
            case '"':
            case '\\':
              Append(c);
              break;
            default:
              Append('\\');
              Append(c);
              break;
          }
        } else {
          Append(*p);
        }
        break;

      default:
        __builtin_unreachable();
    }
  }
}
