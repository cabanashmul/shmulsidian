# Claude Code Commands

Pre-configured commands to enhance your Claude Code + Obsidian workflow.

## Available Commands

### 🤔 thinking-partner

Engage Claude as a thinking partner for exploring complex problems.

```
/thinking-partner
```

Best for: Brainstorming, problem exploration, developing ideas

### 📥 inbox-processor

Process and organize items in your Inbox folder.

```
/inbox-processor
```

Best for: Weekly inbox cleanup, organizing captures

### 🔍 research-assistant

Conduct thorough research on any topic using your vault.

```
/research-assistant
```

Best for: Deep dives, literature reviews, knowledge synthesis

### 📅 daily-review

End-of-day review to capture progress and plan tomorrow.

```
/daily-review
```

Best for: Daily shutdown ritual, reflection

### 📊 weekly-synthesis

Create a comprehensive synthesis of the week's work.

```
/weekly-synthesis
```

Best for: Weekly reviews, pattern recognition

## Creating Custom Commands

1. Create a new `.md` file in this directory
2. Name it descriptively (kebab-case)
3. Structure it with:
   - Clear role definition
   - Specific process steps
   - Expected output format
   - Tips and constraints

## Using Commands

### Method 1: Direct (in Claude Code)

```
/[command-name]
```

### Method 2: Reference in Chat

```
Use the thinking-partner command to help me explore [topic]
```

### Method 3: Manual

```
Follow the instructions in .claude/commands/[command].md
```

## Tips

- Commands are just structured prompts
- Modify them based on your needs
- Combine commands for complex workflows
- Share your custom commands with the community

## Command Ideas

Consider creating commands for:

- Project retrospectives
- Meeting notes processing
- Book notes extraction
- Idea development
- Content planning
- Learning path creation
- Decision analysis

Remember: The best commands emerge from your actual workflows.
