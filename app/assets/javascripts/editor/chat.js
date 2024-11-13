document.addEventListener('turbolinks:load', function () {
    var conversationBox = document.getElementById('conversation-box');
    var promptInput = document.getElementById('prompt-input');
    var sendButton = document.getElementById('send-ai-button');
    var chatForm = document.querySelector('.chat-form');

    // Function to scroll to the bottom of the conversation box
    function scrollToBottom() {
        if (conversationBox) {
            conversationBox.scrollTop = conversationBox.scrollHeight;
        }
    }

    // Auto-scroll to the bottom on page load
    if (conversationBox) {
        scrollToBottom();
    }

    // Automatically scroll to the bottom when the send button is clicked
    if (sendButton) {
        sendButton.addEventListener('click', function () {
            scrollToBottom();
        });
    }

    // Automatically scroll to the bottom when the form is submitted (Enter key)
    if (promptInput) {
        promptInput.addEventListener('keypress', function (event) {
            if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault(); // Prevent newline on Enter
                chatForm.submit(); // Submit the form
                scrollToBottom(); // Scroll to the bottom after submitting
            }
        });

        // Dynamically adjust the height of the prompt box based on content length
        promptInput.addEventListener('input', function () {
            this.style.height = 'auto'; // Reset height
            this.style.height = (this.scrollHeight + 2) + 'px'; // Set height to fit content + small padding
        });
    }

    // Auto-scroll after form submission (using AJAX)
    document.addEventListener('ajax:complete', function () {
        scrollToBottom();
    });
});
