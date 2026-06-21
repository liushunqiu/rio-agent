#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum RiskLevel {
    Safe,
    Normal,
    Dangerous,
}

pub struct CommandClassifier;

impl CommandClassifier {
    pub fn classify(command: &str) -> RiskLevel {
        let command = command.trim();

        if command.is_empty() {
            return RiskLevel::Safe;
        }

        let tokens = Self::tokenize(command);
        Self::classify_tokens(&tokens)
    }

    fn tokenize(command: &str) -> Vec<String> {
        let mut tokens = Vec::new();
        let mut current = String::new();
        let mut in_quotes = false;
        let mut quote_char = ' ';

        for ch in command.chars() {
            match ch {
                '"' | '\'' if !in_quotes => {
                    in_quotes = true;
                    quote_char = ch;
                    current.push(ch);
                }
                c if in_quotes && c == quote_char => {
                    in_quotes = false;
                    current.push(c);
                }
                ' ' | '\t' if !in_quotes => {
                    if !current.is_empty() {
                        tokens.push(current.clone());
                        current.clear();
                    }
                }
                '|' | ';' | '&' if !in_quotes => {
                    if !current.is_empty() {
                        tokens.push(current.clone());
                        current.clear();
                    }
                    tokens.push(ch.to_string());
                }
                _ => current.push(ch),
            }
        }

        if !current.is_empty() {
            tokens.push(current);
        }

        tokens
    }

    fn classify_tokens(tokens: &[String]) -> RiskLevel {
        if tokens.is_empty() {
            return RiskLevel::Safe;
        }

        let mut max_risk = RiskLevel::Safe;

        let mut i = 0;
        while i < tokens.len() {
            let token = &tokens[i];

            if token == "|" || token == ";" || token == "&&" || token == "||" {
                i += 1;
                continue;
            }

            let command = token.as_str();
            let risk = Self::classify_single_command(command, &tokens[i..]);

            if risk > max_risk {
                max_risk = risk;
            }

            // Skip to next operator or end
            i += 1;
            while i < tokens.len() && tokens[i] != "|" && tokens[i] != ";" && tokens[i] != "&&" && tokens[i] != "||" {
                i += 1;
            }
        }

        max_risk
    }

    fn classify_single_command(command: &str, remaining_tokens: &[String]) -> RiskLevel {
        let dangerous_commands = [
            "rm", "rmdir", "del", "format", "mkfs",
            "dd", "shred", "fdisk", "parted",
            "sudo", "su", "doas",
            "kill", "killall", "pkill",
            "curl", "wget", "fetch",
            "chmod", "chown", "chgrp",
        ];

        let safe_commands = [
            "ls", "dir", "cat", "more", "less", "head", "tail",
            "echo", "pwd", "cd", "which", "where",
            "git", "grep", "find", "awk", "sed",
            "diff", "wc", "sort", "uniq",
        ];

        if dangerous_commands.contains(&command) {
            if command == "rm" && Self::has_flag(remaining_tokens, &["-rf", "-fr", "-r", "-f"]) {
                return RiskLevel::Dangerous;
            }
            if command == "kill" && Self::has_flag(remaining_tokens, &["-9", "-KILL"]) {
                return RiskLevel::Dangerous;
            }
            return RiskLevel::Dangerous;
        }

        if safe_commands.contains(&command) {
            if (command == "sed" || command == "awk") && Self::has_flag(remaining_tokens, &["-i"]) {
                return RiskLevel::Normal;
            }
            return RiskLevel::Safe;
        }

        RiskLevel::Normal
    }

    fn has_flag(tokens: &[String], flags: &[&str]) -> bool {
        tokens.iter().any(|t| flags.contains(&t.as_str()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_safe_commands() {
        assert_eq!(CommandClassifier::classify("ls -la"), RiskLevel::Safe);
        assert_eq!(CommandClassifier::classify("cat file.txt"), RiskLevel::Safe);
        assert_eq!(CommandClassifier::classify("git status"), RiskLevel::Safe);
        assert_eq!(CommandClassifier::classify("grep pattern file"), RiskLevel::Safe);
    }

    #[test]
    fn test_dangerous_commands() {
        assert_eq!(CommandClassifier::classify("rm -rf /"), RiskLevel::Dangerous);
        assert_eq!(CommandClassifier::classify("sudo rm file"), RiskLevel::Dangerous);
        assert_eq!(CommandClassifier::classify("kill -9 123"), RiskLevel::Dangerous);
        assert_eq!(CommandClassifier::classify("curl http://example.com"), RiskLevel::Dangerous);
    }

    #[test]
    fn test_normal_commands() {
        assert_eq!(CommandClassifier::classify("npm install"), RiskLevel::Normal);
        assert_eq!(CommandClassifier::classify("cargo build"), RiskLevel::Normal);
        assert_eq!(CommandClassifier::classify("sed -i 's/foo/bar/' file"), RiskLevel::Normal);
    }

    #[test]
    fn test_compound_commands() {
        assert_eq!(CommandClassifier::classify("ls -la && cat file.txt"), RiskLevel::Safe);
        assert_eq!(CommandClassifier::classify("git status | grep modified"), RiskLevel::Safe);
        assert_eq!(CommandClassifier::classify("ls ; rm -rf /"), RiskLevel::Dangerous);
    }
}
