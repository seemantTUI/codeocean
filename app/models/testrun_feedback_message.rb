# app/models/testrun_feedback_message.rb
class TestrunFeedbackMessage < ApplicationRecord
  belongs_to :testrun

  validates :feedback_message, presence: true

  def self.create_for(testrun, output, assessment, exercise_file, reference_implementation_file)
    exercise = testrun.submission.exercise.description
    difficulty = testrun.submission.exercise.expected_difficulty
    test_results = output[:stderr]
    learner_solution = exercise_file.content
    model_solution = reference_implementation_file.content
    error_messages = assessment[:error_messages]

    # Check if a feedback message already exists
    existing_message = find_by(testrun: testrun)
    return existing_message if existing_message

    # Determine expertise level based on difficulty
    expertise_level = map_difficulty_to_expertise(difficulty)

    # Determine error type
    error_type = determine_error_type(error_messages, test_results)

    # Generate feedback message
    feedback_prompt = load_prompt(expertise_level, error_type, learner_solution, exercise, test_results, model_solution)
    feedback_message = generate_feedback_message(feedback_prompt)

    # Create and save the feedback message
    create!(testrun: testrun, feedback_message: feedback_message)
  end

  private

  def self.map_difficulty_to_expertise(difficulty)
    case difficulty
    when 1..3 then 'Beginner'
    when 4..6 then 'Advanced'
    when 7..10 then 'Expert'
    else 'Unknown'
    end
  end

  def self.determine_error_type(error_messages, test_results)
    if syntax_error?(error_messages)
      'syntax_error'
    elsif runtime_error?(error_messages, test_results)
      'runtime_error'
    elsif logical_error?(error_messages, test_results)
      'logical_error'
    else
      'unknown_error'
    end
  end

  def self.syntax_error?(error_messages)
    error_messages.nil?
  end

  def self.runtime_error?(error_messages, test_results)
    !error_messages.nil? && !test_results_has_assertions?(test_results)
  end

  def self.logical_error?(error_messages, test_results)
    !error_messages.nil? && test_results_has_assertions?(error_messages)
  end

  def self.test_results_has_assertions?(test_results)
    assertion_keywords = ['Assertion', 'Expected', 'should', 'must', 'assert']
    assertion_keywords.any? { |keyword| test_results.include?(keyword) }
  end

  def self.load_prompt(expertise_level, error_type, learner_solution, task, error_message, model_solution)
    # Define absolute paths based on expertise level and error type
    prompt_template_map = {
      'Beginner' => {
        'syntax_error' => BEGINNER_SYNTAX,
        'runtime_error' => BEGINNER_RUNTIME,
        'logical_error' => BEGINNER_LOGICAL
      },
      'Advanced' => {
        'syntax_error' => ADVANCED_SYNTAX,
        'runtime_error' => ADVANCED_RUNTIME,
        'logical_error' => ADVANCED_LOGICAL
      },
      'Expert' => {
        'runtime_error' => EXPERT_RUNTIME,
        'logical_error' => EXPERT_LOGICAL
      }
    }

    prompt_template = prompt_template_map.dig(expertise_level, error_type)

    # Read and format the XML prompt
    return "An error has occurred." unless prompt_template

    # Replace placeholders with actual content
    prompt_template.gsub!("[Learner's Code]", learner_solution || "")
    prompt_template.gsub!("[Task]", task || "[Task]")
    prompt_template.gsub!("[Error Message]", error_message || "")
    prompt_template.gsub!("[Model Solution]", model_solution || "")


    prompt_template
  end

  def self.generate_feedback_message(prompt)
    chatgpt_request = ChatGptRequest.new
    chatgpt_request.gpt_response(prompt)
  end
  BEGINNER_SYNTAX = "<prompt>
    <case>
        1-1 Syntax Error - Beginner
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3>
            The hint you generate should, to fulfill requirements 7, 8, and 9, take into account the task of the programming assignment, which is delimited by %%%.
        </instruction_3>
        <instruction_4>
            The hint you generate should, to fulfill requirement 10, definitely take into account the error message that the code caused. This error message is delimited by $$$.
        </instruction_4>
        <instruction_5>
            Requirements 6, 7, 8, 9, 10, and 11 should each be met in their own separate paragraph in the hint.
        </instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback>6. The hint must contain a description or indication of the correct solution. This part should be marked with \"(1)\" in your hint. This part should describe where something should be in the code without giving a code example. Your hint should relate specifically to the problematic part of the code! Do not describe the error, but the correct solution!</requirement_KCR-feedback>
        <requirement_KTC-TR-feedback>7. The hint must contain rules, restrictions, or requirements of the task – in the form of hints to requirements in the task. For example, if a requirement is that a specific predefined method must be used or a method from a specific library must not be used. This part should be marked with \"(2)\" in your hint. Only mention task requirements that directly relate to the code error! Do not mention unrelated requirements!</requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback>8. The hint must contain conceptual knowledge needed for the task – in the form of explanations of fundamental task concepts. This part should be marked with \"(3)\" in your hint.</requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback>9. The hint must contain conceptual knowledge needed for the task – in the form of examples that clarify fundamental concepts of the task. This part should be marked with \"(4)\" in your hint. Refer to the concept you selected in response to requirement number 8. Provide an original, specific example implementing the fundamental concept that does not relate to the current programming task! Be sure to include a code snippet to support your example!</requirement_KC-EXA-feedback>
        <requirement_KM-feedback>10. The hint must describe compiler or interpreter errors. Compiler or interpreter errors are syntax errors (incorrect spelling, missing brackets). This part should be marked with \"(5)\" in your hint. Provide a detailed explanation of the error itself, without steps to fix it.</requirement_KM-feedback>
        <requirement_KH-EC-feedback>11. The hint must contain knowledge about the learner's next steps for resolving this type of error. Relate this to fixing the kind of error present! This part should be marked with \"(6)\" in your hint. Explain the general steps the learner can take next, without showing the exact solution to the error, such as “Change this in line X”! Instead, provide general steps like: “Research this topic online,” “Learn more about this,” “Adjust your code accordingly,” or “Test the output of your code.”</requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter>$$$</delimiter>
            <description>Error message caused by the code:</description>
            <content>[Error Message]</content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </model_solution>
    </input>
</prompt>"
  BEGINNER_RUNTIME = "<prompt>
    <case>
        3-1 Runtime Error - Beginner
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3>
            The hint you generate should, to fulfill requirements 7, 8, and 9, take into account the task of the programming assignment, which is delimited by %%%.
        </instruction_3>
        <instruction_4>
            First, systematically check what error is present in the code, and respond to requirement number 10 accordingly! Locate the error in the learner's code, delimited by \"\"\"! Also, take into account the error message generated during code execution, delimited by $$$. Answer requirement 10 first, then the remaining requirements!
        </instruction_4>
        <instruction_5>
            Requirements 6, 7, 8, 9, 10, and 11 should each be met in their own separate paragraph in the hint.
        </instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback>6. The hint must contain a description or suggestion of the correct solution. This part should be marked with “(1)” in your hint. It should describe what should be present at a specific location in the code without giving a code example. Your hint must relate specifically to the problematic part of the code! Do not describe the existing error, but the correct solution!</requirement_KCR-feedback>
        <requirement_KTC-TR-feedback>7. The hint must contain rules, restrictions, or requirements of the task in the form of hints to task requirements. For example, if a specific predefined method must be used or a method from a specific library must not be used. This part should be marked with “(2)” in your hint. Only mention requirements from the task that directly relate to the error in the code! Do not mention irrelevant requirements!</requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback>8. The hint must contain conceptual knowledge needed for the task in the form of explanations of fundamental task concepts. This part should be marked with “(3)” in your hint.</requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback>9. The hint must contain conceptual knowledge needed for the task in the form of examples that clarify fundamental task concepts. This part should be marked with “(4)” in your hint. Refer to the concept you selected in response to requirement number 8. Provide an original, specific example implementing the fundamental concept that does not relate to the current programming task! Be sure to include a code snippet to support your example!</requirement_KC-EXA-feedback>
        <requirement_KM-feedback>10. There is a runtime error in the learner’s code, meaning an error occurs during code execution. Causes of runtime errors can include an infinite loop or memory overflow, among others. The hint must describe this error. This part should be marked with “(5)” in your hint. Provide a description of the runtime error and explain it in detail! Explain what a runtime error is, possibly with an example! Before writing the hint, check the accuracy of your statement about the error, such as whether the programming language used in the code has a compiler or interpreter! Do not output your accuracy check!</requirement_KM-feedback>
        <requirement_KH-EC-feedback>11. The hint must contain knowledge about the learner's next steps for resolving this type of error. Relate this to fixing the kind of error present! This part should be marked with “(6)” in your hint. Explain the general methodical step for fixing the error without giving the exact solution, such as “Change this in line X”! Instead, provide general steps like: “Learn more about this topic,” “Adjust your code accordingly,” or “Test your code output.”</requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter>$$$</delimiter>
            <description>Error message generated by the code:</description>
            <content>[Error Message]</content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </model_solution>
    </input>
</prompt>"
  BEGINNER_LOGICAL = "<prompt>
    <case>
        2-1 Logical Error - Beginner
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3>
            The hint you generate should, to fulfill requirements 7, 8, and 9, take into account the task of the programming assignment, which is delimited by %%%.
        </instruction_3>
        <instruction_4>
            First, systematically check what error is present in the code, and respond to requirement number 10 accordingly! Compare the learner’s code with the model solution to identify the error! Use the learner’s code, delimited by \"\"\", and the model solution, delimited by ***. Answer requirement 10 first, then the remaining requirements!
        </instruction_4>
        <instruction_5>
            Requirements 6, 7, 8, 9, 10, and 11 should each be met in their own separate paragraph in the hint.
        </instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback>6. The hint must contain a description or suggestion of the correct solution. This part should be marked with “(1)” in your hint. It should describe that something should be present at a specific location in the code without giving a code example. Your hint must relate specifically to the problematic part of the code! Do not describe the existing error, but the correct solution!</requirement_KCR-feedback>
        <requirement_KTC-TR-feedback>7. The hint must contain rules, restrictions, or requirements of the task in the form of hints to requirements of the task. For example, if a requirement is that a specific predefined method must be used or a method from a specific library must not be used. This part should be marked with “(2)” in your hint. Only state requirements from the task that directly relate to the error in the code! Do not state irrelevant requirements!</requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback>8. The hint must contain conceptual knowledge needed for the task in the form of explanations of fundamental concepts of the task. This part should be marked with “(3)” in your hint.</requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback>9. The hint must contain conceptual knowledge needed for the task in the form of examples that clarify fundamental task concepts. This part should be marked with “(4)” in your hint. Refer to the concept you selected in response to requirement number 8. Provide an original, specific example implementing the fundamental concept that does not relate to the current programming task! Be sure to include a code snippet to support your example!</requirement_KC-EXA-feedback>
        <requirement_KM-feedback>10. There is a logical error in the learner’s code, meaning the program does not perform what is required by the task. The hint must describe this error. This part should be marked with “(5)” in your hint. Provide a description of the error and explain it in detail! Explain what a logical error is, possibly with an example!</requirement_KM-feedback>
        <requirement_KH-EC-feedback>11. The hint must contain knowledge about the learner's next steps for resolving this type of error. Relate this to fixing the kind of error present! This part should be marked with “(6)” in your hint. Explain the general methodical step for fixing the error without giving the exact solution, such as “Change this in line X”! Instead, provide general steps, like: “Learn more about this topic,” “Adjust your code accordingly,” or “Test the output of your code.”</requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter>***</delimiter>
            <description>Model solution for the programming task:</description>
            <content>[Model Solution]</content>
        </model_solution>
    </input>
</prompt>"
  ADVANCED_SYNTAX = "<prompt>
    <case>
        1-2 Syntax Error - Advanced
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3>
            The hint you generate should, to fulfill requirements 7 and 8, take into account the task of the programming assignment, which is delimited by %%%.
        </instruction_3>
        <instruction_4>
            The hint you generate should, to fulfill requirement 9, definitely take into account the error message that the code caused. This error message is delimited by $$$.
        </instruction_4>
        <instruction_5>
            Requirements 6, 7, 8, 9, and 10 should each be met in their own separate paragraph in the hint.
        </instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback>6. The hint must contain an indication of the correct solution. This part should be marked with “(1)” in your hint. Ensure that only a suggestion is provided! Do not describe what should be in a specific place in the code! Do not explain the existing error but instead hint at the general appearance of the correct code! Do not explain how to modify the code to solve the error! Under no circumstances should you indicate which parts of the code should be removed or edited!</requirement_KCR-feedback>
        <requirement_KTC-TR-feedback>7. Indicate which subtask in the task, delimited by %%%, has a requirement that has not been met due to the error. For example, if a requirement is that a specific predefined method must be used or a method from a specific library must not be used. This part should be marked with “(2)” in your hint. Select the subtask in the task where the relevant requirement is violated by the error! Only state: “Due to the error, a requirement in subtask [Subtask from the task where the requirement is unmet] is not fulfilled.” Do not provide further information!</requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback></requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback>8. The hint must contain conceptual knowledge needed for the task – in the form of examples that clarify fundamental task concepts. This part should be marked with “(3)” in your hint. Provide an original, specific example implementing the fundamental concept that does not relate to the current programming task! Be sure to include a code snippet to support your example!</requirement_KC-EXA-feedback>
        <requirement_KM-feedback>9. There is a syntax error in the code. This part should be marked with “(4)” in your hint. Provide only a short hint consisting solely of the error type “syntax error” and the line of the error – e.g., “See if there is a syntax error on line [line of the error].” Do not give the correct solution or specify what to fix in the code in any way!</requirement_KM-feedback>
        <requirement_KH-EC-feedback>10. The hint must contain knowledge about the learner's next steps for resolving this type of error. Relate this to fixing the kind of error present! This part should be marked with “(5)” in your hint. Specify the next step the learner should take, but do not explain it! For example, you could suggest: “Edit line [line of the error] and research the topic [topic of the error] online.”</requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter>$$$</delimiter>
            <description>Error message caused by the code:</description>
            <content>[Error Message]</content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </model_solution>
    </input>
</prompt>"
  ADVANCED_RUNTIME = "<prompt>
    <case>
        1-2 Syntax Error - Advanced
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3>
            The hint you generate should, to fulfill requirements 7 and 8, take into account the task of the programming assignment, which is delimited by %%%.
        </instruction_3>
        <instruction_4>
            The hint you generate should, to fulfill requirement 9, definitely take into account the error message that the code caused. This error message is delimited by $$$.
        </instruction_4>
        <instruction_5>
            Requirements 6, 7, 8, 9, and 10 should each be met in their own separate paragraph in the hint.
        </instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback>6. The hint must contain an indication of the correct solution. This part should be marked with “(1)” in your hint. Ensure that only a suggestion is provided! Do not describe what should be in a specific place in the code! Do not explain the existing error but instead hint at the general appearance of the correct code! Do not explain how to modify the code to solve the error! Under no circumstances should you indicate which parts of the code should be removed or edited!</requirement_KCR-feedback>
        <requirement_KTC-TR-feedback>7. Indicate which subtask in the task, delimited by %%%, has a requirement that has not been met due to the error. For example, if a requirement is that a specific predefined method must be used or a method from a specific library must not be used. This part should be marked with “(2)” in your hint. Select the subtask in the task where the relevant requirement is violated by the error! Only state: “Due to the error, a requirement in subtask [Subtask from the task where the requirement is unmet] is not fulfilled.” Do not provide further information!</requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback></requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback>8. The hint must contain conceptual knowledge needed for the task – in the form of examples that clarify fundamental task concepts. This part should be marked with “(3)” in your hint. Provide an original, specific example implementing the fundamental concept that does not relate to the current programming task! Be sure to include a code snippet to support your example!</requirement_KC-EXA-feedback>
        <requirement_KM-feedback>9. There is a syntax error in the code. This part should be marked with “(4)” in your hint. Provide only a short hint consisting solely of the error type “syntax error” and the line of the error – e.g., “See if there is a syntax error on line [line of the error].” Do not give the correct solution or specify what to fix in the code in any way!</requirement_KM-feedback>
        <requirement_KH-EC-feedback>10. The hint must contain knowledge about the learner's next steps for resolving this type of error. Relate this to fixing the kind of error present! This part should be marked with “(5)” in your hint. Specify the next step the learner should take, but do not explain it! For example, you could suggest: “Edit line [line of the error] and research the topic [topic of the error] online.”</requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter>$$$</delimiter>
            <description>Error message caused by the code:</description>
            <content>[Error Message]</content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </model_solution>
    </input>
</prompt>"
  ADVANCED_LOGICAL = "<prompt>
    <case>
        2-2 Logical Error - Advanced
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3>
            The hint you generate should, to fulfill requirements 7 and 8, take into account the task of the programming assignment, which is delimited by %%%.
        </instruction_3>
        <instruction_4>
            First, systematically check what error is present in the code, and respond to requirement number 9 accordingly! Compare the learner’s code with the model solution to identify the error! Use the learner’s code, delimited by \"\"\", and the model solution, delimited by ***. Answer requirement 9 first, then the remaining requirements!
        </instruction_4>
        <instruction_5>
            Requirements 6, 7, 8, 9, and 10 should each be met in their own separate paragraph in the hint.
        </instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback>6. The hint must contain an indication of the correct solution. This part should be marked with “(1)” in your hint. Ensure that only a suggestion is provided! Do not describe what should be in a specific place in the code! Do not explain the existing error but instead hint at the general appearance of the correct code! Do not explain how to modify the code to solve the error! Under no circumstances should you indicate which parts of the code should be removed or edited!</requirement_KCR-feedback>
        <requirement_KTC-TR-feedback>7. Indicate which subtask in the task, delimited by %%%, has a requirement that has not been met due to the error. For example, if a requirement is that a specific predefined method must be used or a method from a specific library must not be used. This part should be marked with “(2)” in your hint. Select the subtask in the task where the relevant requirement is violated by the error! Only state: “Due to the error, a requirement in subtask [Subtask from the task where the requirement is unmet] is not fulfilled.” Do not provide further information!</requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback></requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback>8. The hint must contain conceptual knowledge needed for the task in the form of examples that clarify fundamental task concepts. This part should be marked with “(3)” in your hint. Provide an original, specific example implementing the fundamental concept that does not relate to the current programming task! Be sure to include a code snippet to support your example!</requirement_KC-EXA-feedback>
        <requirement_KM-feedback>9. There is a logical error in the learner’s code, meaning the program does not perform what is required by the task. The hint must describe this error. This part should be marked with “(4)” in your hint. Provide a description of the error and explain it in detail!</requirement_KM-feedback>
        <requirement_KH-EC-feedback>10. The hint must contain knowledge about the learner's next steps for resolving this type of error. Relate this to fixing the kind of error present! This part should be marked with “(5)” in your hint. Specify the next step the learner should take, but do not explain it! For example, you could suggest: “Edit line [line of the error]” or “Test your code output again after editing.” Mention the line to edit but do not explain how it should be edited!</requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter>***</delimiter>
            <description>Model solution for the programming task:</description>
            <content>[Model Solution]</content>
        </model_solution>
    </input>
</prompt>"
  EXPERT_LOGICAL = "<prompt>
    <case>
        2-3 Logical Error - Expert
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3></instruction_3>
        <instruction_4>
            First, systematically check what error is present in the code, and respond to requirement number 6 accordingly! Compare the learner’s code with the model solution to identify the error! Use the learner’s code, delimited by \"\"\", and the model solution, delimited by ***.
        </instruction_4>
        <instruction_5></instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback></requirement_KCR-feedback>
        <requirement_KTC-TR-feedback></requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback></requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback></requirement_KC-EXA-feedback>
        <requirement_KM-feedback>6. There is a logical error in the learner’s code, meaning the program does not perform what is required by the task. The hint must describe this error. This part should be marked with “(1)” in your hint. Briefly name the error only! Do not explain the error or suggest any corrective action! Only quote the line in the code where the error is and state that a logical error is present!</requirement_KM-feedback>
        <requirement_KH-EC-feedback></requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter>***</delimiter>
            <description>Model solution for the programming task:</description>
            <content>[Model Solution]</content>
        </model_solution>
    </input>
</prompt>"
  EXPERT_RUNTIME = "<prompt>
    <case>
        3-3 Runtime Error - Expert
    </case>
    <role>
        You are acting as a tutor for a learner who has encountered a problem in a programming task. Respond in accordance with your role as a tutor in the following!
    </role>
    <instructions>
        <instruction_1>
            Your task is to formulate a hint for the learner's code, delimited by \"\"\".
        </instruction_1>
        <instruction_2>
            The hint you generate must meet each requirement delimited by ###.
        </instruction_2>
        <instruction_3></instruction_3>
        <instruction_4>
            First, systematically check what error is present in the code, and respond to requirement number 6 accordingly! Locate the error in the learner's code, delimited by \"\"\"! Also, take into account the error message generated during code execution, delimited by $$$.
        </instruction_4>
        <instruction_5></instruction_5>
        <instruction_6>
            Proceed systematically! Reflect on your approach! However, only output the hint, not your approach!
        </instruction_6>
    </instructions>
    <requirements>
        <delimiter>###</delimiter>
        <requirement_1>The hint must identify and name an error in the code.</requirement_1>
        <requirement_2>The hint must not identify non-existent errors.</requirement_2>
        <requirement_3>The hint must not contain content unrelated to the error.</requirement_3>
        <requirement_4>The hint must not contain code that could be understood as a solution.</requirement_4>
        <requirement_5>The hint must not contain test cases.</requirement_5>
        <requirement_KCR-feedback></requirement_KCR-feedback>
        <requirement_KTC-TR-feedback></requirement_KTC-TR-feedback>
        <requirement_KC-EXP-feedback></requirement_KC-EXP-feedback>
        <requirement_KC-EXA-feedback></requirement_KC-EXA-feedback>
        <requirement_KM-feedback>6. There is a runtime error in the learner’s code, meaning an error occurs during code execution. The hint must describe this error. This part should be marked with “(1)” in your hint. Briefly name the error only! Do not explain the error or suggest any corrective action! Quote the line in the code where the error is and state that a runtime error is present! Identify the cause of the runtime error (such as infinite loop, division by zero, infinite recursion, etc.) and state: “Warning: [Cause of runtime error]!” Do not provide any further information about the error!</requirement_KM-feedback>
        <requirement_KH-EC-feedback></requirement_KH-EC-feedback>
    </requirements>
    <input>
        <code name=\"Learner's Code\" type=\"string\">
            <delimiter>\"\"\"</delimiter>
            <description>Learner's Code:</description>
            <content>[Learner's Code]</content>
        </code>
        <programming_task name=\"Task\" type=\"string\">
            <delimiter>%%%</delimiter>
            <description>Task for the programming assignment:</description>
            <content>[Task]</content>
        </programming_task>
        <error_message name=\"Error Message\" type=\"string\">
            <delimiter>$$$</delimiter>
            <description>Error message generated by the code:</description>
            <content>[Error Message]</content>
        </error_message>
        <model_solution name=\"Model Solution\" type=\"string\">
            <delimiter></delimiter>
            <description></description>
            <content></content>
        </model_solution>
    </input>
</prompt>"








end
