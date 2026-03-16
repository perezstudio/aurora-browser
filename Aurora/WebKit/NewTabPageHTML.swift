import Foundation

enum NewTabPageHTML {
    static func generate() -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>New Tab</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif;
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
                    color: #e0e0e0;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    height: 100vh;
                    overflow: hidden;
                    -webkit-user-select: none;
                }
                #clock {
                    font-size: 96px;
                    font-weight: 200;
                    letter-spacing: -2px;
                    color: #ffffff;
                    text-shadow: 0 2px 20px rgba(124, 106, 247, 0.3);
                }
                #date {
                    font-size: 20px;
                    font-weight: 400;
                    color: rgba(255, 255, 255, 0.6);
                    margin-top: 8px;
                }
                #greeting {
                    font-size: 28px;
                    font-weight: 300;
                    color: rgba(255, 255, 255, 0.8);
                    margin-bottom: 40px;
                }
            </style>
        </head>
        <body>
            <div id="greeting"></div>
            <div id="clock"></div>
            <div id="date"></div>
            <script>
                function updateClock() {
                    const now = new Date();
                    const hours = now.getHours();
                    const mins = String(now.getMinutes()).padStart(2, '0');

                    document.getElementById('clock').textContent =
                        (hours % 12 || 12) + ':' + mins;

                    const options = { weekday: 'long', month: 'long', day: 'numeric' };
                    document.getElementById('date').textContent =
                        now.toLocaleDateString('en-US', options);

                    let greeting = 'Good evening';
                    if (hours < 12) greeting = 'Good morning';
                    else if (hours < 17) greeting = 'Good afternoon';
                    document.getElementById('greeting').textContent = greeting;
                }
                updateClock();
                setInterval(updateClock, 1000);
            </script>
        </body>
        </html>
        """
    }
}
