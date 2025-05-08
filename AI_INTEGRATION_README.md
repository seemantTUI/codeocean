# AI Feedback Integration in CodeOcean

This project integrates ChatGPT into CodeOcean to provide automated feedback for both **Request for Comments (RFCs)** and **test results**.

## Prerequisites

- **API Key:** Stored securely via Rails credentials  
  To edit the API key, use the following command:  
  Open the rails credentials using an editor from the command line.
  ```bash
  EDITOR="nano" bin/rails credentials:edit
  ```  
  Then add the API key like this in the rails credentials:  
  ```yaml
  openai:
    api_key: your_api_key
  ```  
  If the environment is production, use:  
  ```bash
  RAILS_ENV=production EDITOR="nano" bin/rails credentials:edit
  ```  
  and add the key.
  

- **Internal User:** Requires an internal user (`chatgpt@example.org`) to create comments
- **Gem Required:** `gem 'ruby-openai'`

## Overview

- **AI API:** OpenAI Chat Completions
- **Jobs:** Asynchronous processing via Solid Queue
- **Frontend:** Adds "Request Feedback from AI" buttons for test results on Score

## Key Components

###  ChatGPT Service

Encapsulates API communication with ChatGPT.

- **Implementation:** [`app/services/chat_gpt_service/chat_gpt_request.rb`](app/services/chat_gpt_service/chat_gpt_request.rb)
- **Prompt files:** [`app/services/chat_gpt_service/chat_gpt_prompts/`](app/services/chat_gpt_service/chat_gpt_prompts/) (EN and DE versions)
- **Structured Output Schema:** [`app/services/chat_gpt_service/chat_gpt_prompts/response_format.json`](app/services/chat_gpt_service/chat_gpt_prompts/response_format.json)

###  ChatGPT Helper

Responsible for formatting prompts and parsing responses.

- [`app/helpers/chat_gpt_helper.rb`](app/helpers/chat_gpt_helper.rb)
- `format_prompt`: Loads locale-specific prompt templates and replaces placeholders in the prompt from the application.
- `format_response`: Parses structured JSON response from chatGPT to create general comments (line 0) and line comments for RFC.

###  Automatic Comment Job (RFC)

Handles background comment generation when students submit a Request for Comments.

- **Job class:** [`GenerateAutomaticCommentsJob`](app/jobs/generate_automatic_comments_job.rb)
- **Service:** Uses `ChatGptRequest` to communicate with the API
- **Process:**
  1. Prompts are built from student code and context
  2. API response is parsed
  3. General and line-specific comments are created
  4. Emails are sent using Solid Queue

### ️Request Feedback From AI

Allows students to request feedback per test result after scoring.

- **Output modification:**  
  [`app/models/submission.rb`](app/models/submission.rb)  
  Adds `testrun_id` to each test result:
  ```ruby
  output.merge!(filename:, message: feedback_message(file, output), weight: file.weight, hidden_feedback: file.hidden_feedback, testrun_id: testrun.id)
  ```

- **Frontend integration:**  
  [`app/assets/javascripts/editor/editor.js.erb`](app/assets/javascripts/editor/editor.js.erb)  
  ```js
  card.attr('data-testrun-id', result.testrun_id); // Add testrun_id to the card
  ```

- **Triggering feedback request:**  
  [`app/assets/javascripts/editor.js`](app/assets/javascripts/editor.js)  
  Handles button click, calls backend route, and updates the UI with the ChatGPT feedback.

- **Route and logic:**  
  - [`app/controllers/submissions_controller.rb`](app/controllers/submissions_controller.rb): Handles `/testrun_ai_feedback_message` route  
  - [`app/models/testrun.rb`](app/models/testrun.rb): Contains `generate_ai_feedback` method that builds prompt and fetches response

###  Exercise-Level Controls

Instructors can toggle AI features per exercise using boolean flags:

- `allow_ai_comment_for_rfc`: Enables RFC-based AI feedback
- `allow_ai_feedback_on_score`: Enables test-based feedback
