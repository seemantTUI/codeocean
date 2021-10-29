CodeOceanEditorEvaluation = {
    chunkBuffer: [{streamedResponse: true}],

    /**
     * Scoring-Functions
     */
    scoreCode: function (event) {
        event.preventDefault();
        this.stopCode(event);
        this.clearScoringOutput();
        $('#submit').addClass("d-none");
        this.createSubmission('#assess', null, function (response) {
            this.showSpinner($('#assess'));
            $('#score_div').removeClass('d-none');
            var url = response.score_url;
            this.initializeSocketForScoring(url);
        }.bind(this));
    },

    handleScoringResponse: function (results) {
        this.printScoringResults(results);
        var score = _.reduce(results, function (sum, result) {
            return sum + result.score * result.weight;
        }, 0).toFixed(2);
        $('#score').data('score', score);
        this.renderScore();
        this.showSubmitButton();
    },

    showSubmitButton: function () {
        if (this.submission_deadline || this.late_submission_deadline) {
            const now = new Date();
            if (now <= this.submission_deadline) {
                // before_deadline
                // default is btn-success, so no change in color
                $('#submit').get(0).lastChild.nodeValue = I18n.t('exercises.editor.submit_on_time');
            } else if (now > this.submission_deadline && this.late_submission_deadline && now <= this.late_submission_deadline) {
                // within_grace_period
                $('#submit').removeClass("btn-success btn-warning").addClass("btn-warning");
                $('#submit').get(0).lastChild.nodeValue = I18n.t('exercises.editor.submit_within_grace_period');
            } else if (this.late_submission_deadline && now > this.late_submission_deadline || now > this.submission_deadline) {
                // after_late_deadline
                $('#submit').removeClass("btn-success btn-warning btn-danger").addClass("btn-danger");
                $('#submit').get(0).lastChild.nodeValue = I18n.t('exercises.editor.submit_after_late_deadline');
            }
        }
        $('#submit').removeClass("d-none");
    },

    printScoringResult: function (result, index) {
        if (result === undefined || result === null) {
            return;
        }

        $('#results').show();
        let card;
        if (result.file_role === 'teacher_defined_linter') {
            card = $('#linter-dummies').children().first().clone();
        } else {
            card = $('#test-dummies').children().first().clone();
        }
        if (card.isPresent()) {
            // the card won't be present if @embed_options[:hide_test_results] == true
            this.populateCard(card, result, index);
            $('#results ul').first().append(card);
        }
    },

    printScoringResults: function (response) {
        response = (Array.isArray(response)) ? response : [response]
        const test_results = response.filter(function(x) {
            if (x === undefined || x === null) {
                return false;
            }
            switch (x.file_role) {
                case 'teacher_defined_test':
                    return true;
                case 'teacher_defined_linter':
                    return true;
                default:
                    return false;
            }
        });

        $('#results ul').first().html('');
        $('.test-count .number').html(test_results.length);
        this.clearOutput();

        _.each(test_results, function (result, index) {
            // based on https://stackoverflow.com/questions/8511281/check-if-a-value-is-an-object-in-javascript
            if (result === Object(result)) {
                this.printOutput(result, false, index);
                this.printScoringResult(result, index);
            }
        }.bind(this));

        if (_.some(response, function (result) {
            return result.status === 'timeout';
        })) {
            this.showTimeoutMessage();
        }
        if (_.some(response, function (result) {
            return result.status === 'container_depleted';
        })) {
            this.showContainerDepletedMessage();
        }
        if (this.qa_api) {
            // send test response to QA
            this.qa_api.executeCommand('syncOutput', [response]);
        }
    },

    renderScore: function () {
        var score = parseFloat($('#score').data('score'));
        var maximum_score = parseFloat($('#score').data('maximum-score'));
        if (score >= 0 && score <= maximum_score && maximum_score > 0) {
            var percentage_score = (score / maximum_score * 100).toFixed(0);
            $('.score').html(percentage_score + '%');
        } else {
            $('.score').html(0 + '%');
        }
        this.renderProgressBar(score, maximum_score);
    },

    /**
     * Testing-Logic
     */
    handleTestResponse: function (result) {
        this.clearOutput();
        this.printOutput(result, false, 0);
        if (this.qa_api) {
            this.qa_api.executeCommand('syncOutput', [result]);
        }
        this.showStatus(result);
        this.showOutputBar();
    },

    /**
     * Stop-Logic
     */
    stopCode: function (event) {
        event.preventDefault();
        if (this.isActiveFileStoppable()) {
            this.websocket.send(JSON.stringify({'cmd': 'client_kill'}));
            this.killWebsocket();
            this.cleanUpUI();
        }
    },

    killWebsocket: function () {
        if (this.websocket != null && this.websocket.getReadyState() !== WebSocket.OPEN) {
            return;
        }

        this.websocket.killWebSocket();
        this.websocket.onError(_.noop);
        this.running = false;
    },

    cleanUpUI: function () {
        this.hideSpinner();
        this.toggleButtonStates();
        this.hidePrompt();
    },

    /**
     * Output-Logic
     */
    renderWebsocketOutput: function (msg) {
        var element = this.findOrCreateRenderElement(0);
        element.append(msg.data);
    },

    printWebsocketOutput: function (msg) {
        if (!msg.data || msg.data === "\r") {
            return;
        }
        msg.data = msg.data.replace(/(\r)/gm, "\n");
        var stream = {};
        stream[msg.stream] = msg.data;
        this.printOutput(stream, true, 0);
    },

    clearOutput: function () {
        $('#output pre').remove();
        CodeOceanEditorTurtle.hideCanvas();
    },

    clearScoringOutput: function () {
        $('#results ul').first().html('');
        $('.test-count .number').html(0);
        $('#score').data('score', 0);
        this.renderScore();
        this.clearOutput();
    },

    printOutput: function (output, colorize, index) {
        if (output === undefined || output === null || output.stderr === undefined && output.stdout === undefined) {
            // Prevent empty element with no text at all
            return;
        }

        var element = this.findOrCreateOutputElement(index);
        // Switch all four lines below to enable the output of images and render <IMG/> tags
        if (!colorize) {
            if (output.stdout !== undefined && output.stdout !== '') {
                //element.append(output.stdout)
                element.text(element.text() + output.stdout)
            }

            if (output.stderr !== undefined && output.stderr !== '') {
                //element.append('StdErr: ' + output.stderr);
                element.text('StdErr: ' + element.text() + output.stderr);
            }

        } else if (output.stderr) {
            //element.addClass('text-warning').append(output.stderr);
            element.addClass('text-warning').text(element.text() + output.stderr);
            this.QaApiOutputBuffer.stderr += output.stderr;
        } else if (output.stdout) {
            //element.addClass('text-success').append(output.stdout);
            element.addClass('text-success').text(element.text() + output.stdout);
            this.QaApiOutputBuffer.stdout += output.stdout;
        } else {
            element.addClass('text-muted').text($('#output').data('message-no-output'));
        }
    },

    getDeadlineInformation: function(deadline, translation_key, otherwise) {
        if (deadline !== undefined) {
            let li = document.createElement("li");
            this.submission_deadline = new Date(deadline);
            let deadline_text = I18n.l("time.formats.long", this.submission_deadline);
            deadline_text += ` (${this.getUTCTime(this.submission_deadline, I18n.locale === 'en')})`;
            const bullet_point = I18n.t('exercises.editor.hints.' + translation_key,
                { deadline: deadline_text, otherwise: otherwise })
            let text = $.parseHTML(bullet_point);
            $(li).append(text);
            return li;
        }
    },

    getUTCTime: function(d, use_am_pm) {
        let hour = d.getUTCHours();
        const pm = hour >= 12;
        let hour12 = hour % 12;
        if (!hour12) {
            hour12 += 12;
        }
        hour = hour.toLocaleString('en-US', {minimumIntegerDigits: 2, useGrouping: false})
        const minute = d.getUTCMinutes().toLocaleString('en-US', {minimumIntegerDigits: 2, useGrouping: false})
        const second = d.getUTCSeconds().toLocaleString('en-US', {minimumIntegerDigits: 2, useGrouping: false})
        if (use_am_pm) {
            return `${hour12}:${minute}:${second} ${pm ? 'pm' : 'am'} UTC`;
        } else {
            return `${hour}:${minute}:${second} UTC`;
        }
    },

    initializeDeadlines: function () {
        const deadline = $('#deadline');
        if (deadline) {
            const submission_deadline = deadline.data('submission-deadline');
            const late_submission_deadline = deadline.data('late-submission-deadline');

            const ul = document.createElement("ul");

            if (submission_deadline && late_submission_deadline) {
                ul.append(this.getDeadlineInformation(submission_deadline, 'submission_deadline', ''));
                ul.append(this.getDeadlineInformation(late_submission_deadline, 'late_submission_deadline', ''));
            } else {
                const otherwise_no_points = I18n.t('exercises.editor.hints.otherwise');
                ul.append(this.getDeadlineInformation(submission_deadline, 'submission_deadline', otherwise_no_points));
            }

            $(ul).insertAfter($(deadline).children()[0]);
        }
    }
};
