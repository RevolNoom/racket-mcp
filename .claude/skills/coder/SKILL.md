```yaml
---
name: coder
description: "Use this skill for all coding tasks and code reviews. This skill applies comprehensive coding best practices covering documentation, code structure, readability, performance, and security guidelines. Trigger on any coding-related request including writing new code, reviewing existing code, refactoring, debugging, or discussing code quality."
---

## Coding Best Practices

### Documentation
- **Classes**: Briefly describe what a class does, features it offers
- **Functions**: Briefly describe what a function does, describe function inputs, and an example function call
- **Enums**: Briefly describe what an enum is used for, with additional comments on each enum element if their names are not clear or not descriptive enough

### Code Structure & Performance
- **Avoid using properties**: Create a private member variable, and get set functions instead
- **Early return**: Arrange code for early return whenever possible
- **Function returns**: Functions must explicitly return results and reassign at caller. Do not modify parameters internally
- **Static members**: 
  - Call static members by using the class name
  - Do not qualify a static member defined in a base class with the name of a derived class
- **Return variable**: Return variable, not function call
- **Pass variables**: Pass variables as arguments into function calls, not calculation
- **Object creation**: Create new object via constructors or by default constructor then assign each field. Avoid using initializer
- **Array manipulation**: Use traditional for loop syntax instead of ForEach() function for better performance and control

### Readability
- **Line length**: Limit lines to 65 characters
- **Comments**:
  - Place the comment on a separate line, not at the end of a line of code
  - Begin comment text with an uppercase letter
  - End comment text with a period
  - Insert one space between the comment delimiter and the comment text

### Data Transformation Steps
- **Non-transformative step**: A step that returns an array of same type as input array
  - Reassign results to initial variable whenever possible
  - Examples: Filtering (Where()/filter()), Ordering (OrderBy()/sort())
- **Transformative step**: A step that returns an array of different type from input array
  - If return type is identical to input type, it is considered non-transformative
  - **Rule**: Assigns intermediate results into variables
  - **Rule**: Explain each step with comments

### Input Validation
- **User's inputs**: Must be validated for null
- **Developer's arguments**: Must NOT be validated for null, so that developer's error must be caught as soon as possible

## How to Apply These Practices
When this skill is triggered, the agent should:
1. Review code against these best practices
2. Suggest specific improvements with line numbers or code examples
3. Explain WHY each suggested change improves code quality
4. Prioritize fixes that catch errors early or improve readability
5. Reference specific guidelines when making suggestions
```