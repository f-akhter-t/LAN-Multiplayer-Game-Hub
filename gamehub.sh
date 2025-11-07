#!/bin/bash

PORT=9999
PARTNER_IP=""
MODE="" 
CONNECTED=0

STATS_FILE="game_stats.txt"
declare -A STATS

function init_stats() {
  STATS=(
    [host_wins]=0
    [host_losses]=0
    [host_draws]=0
    [client_wins]=0
    [client_losses]=0
    [client_draws]=0
  )
  if [[ -f "$STATS_FILE" ]]; then
    while IFS='=' read -r key value; do
      STATS[$key]=$value
    done <"$STATS_FILE"
  fi
}

function save_stats() {
  for key in "${!STATS[@]}"; do
    echo "$key=${STATS[$key]}"
  done >"$STATS_FILE"
}

function update_stats() {
  local result=$1

  case $result in
  host_win)
    ((STATS[host_wins]++))
    ((STATS[client_losses]++))
    ;;
  client_win)
    ((STATS[client_wins]++))
    ((STATS[host_losses]++))
    ;;
  draw)
    ((STATS[host_draws]++))
    ((STATS[client_draws]++))
    ;;
  esac

  save_stats

  if [[ $MODE == "host" ]]; then
    send_msg "STATS_UPDATE ${STATS[host_wins]} ${STATS[host_losses]} ${STATS[host_draws]} ${STATS[client_wins]} ${STATS[client_losses]} ${STATS[client_draws]}"
  fi
}

function show_stats() {
  clear
  echo "========== GAME STATISTICS =========="

  if [[ $MODE == "client" ]]; then
    send_msg "STATS_REQUEST"
    while true; do
      msg=$(recv_msg)
      if [[ "$msg" == STATS_UPDATE* ]]; then
        IFS=' ' read -r cmd hw hl hd cw cl cd <<< "$msg"
        STATS=(
          [host_wins]=$hw
          [host_losses]=$hl
          [host_draws]=$hd
          [client_wins]=$cw
          [client_losses]=$cl
          [client_draws]=$cd
        )
        save_stats
        break
      fi
    done
  fi

  if [[ $MODE == "host" ]]; then
    while read -t 0.1 -r msg; do
      if [[ "$msg" == "STATS_REQUEST" ]]; then
        send_msg "STATS_UPDATE ${STATS[host_wins]} ${STATS[host_losses]} ${STATS[host_draws]} ${STATS[client_wins]} ${STATS[client_losses]} ${STATS[client_draws]}"
      fi
    done < <(recv_msg)
  fi

  if [[ $MODE == "host" ]]; then
    echo "YOUR STATS (as HOST):"
    echo "  Wins: ${STATS[host_wins]}"
    echo "  Losses: ${STATS[host_losses]}"
    echo "  Draws: ${STATS[host_draws]}"
    echo ""
    echo "OPPONENT STATS (as CLIENT):"
    echo "  Wins: ${STATS[client_wins]}"
    echo "  Losses: ${STATS[client_losses]}"
    echo "  Draws: ${STATS[client_draws]}"
  else
    echo "YOUR STATS (as CLIENT):"
    echo "  Wins: ${STATS[client_wins]}"
    echo "  Losses: ${STATS[client_losses]}"
    echo "  Draws: ${STATS[client_draws]}"
    echo ""
    echo "OPPONENT STATS (as HOST):"
    echo "  Wins: ${STATS[host_wins]}"
    echo "  Losses: ${STATS[host_losses]}"
    echo "  Draws: ${STATS[host_draws]}"
  fi

  echo "====================================="
  read -rp "Press enter to continue..."
}

DICT_FILE="/usr/share/dict/words"
if [[ ! -f "$DICT_FILE" ]]; then
  DICT_FILE=""
fi

function setup_connection() {
  echo "Choose mode: (h)ost or (c)lient?"
  read -r mode_choice

  if [[ $mode_choice == "h" ]]; then
    MODE="host"
    echo "Waiting for connection on port $PORT..."
    coproc NC_PROC { nc -l -p $PORT; }
    exec 3<&"${NC_PROC[0]}"
    exec 4>&"${NC_PROC[1]}"
    CONNECTED=1
  elif [[ $mode_choice == "c" ]]; then
    MODE="client"
    echo -n "Enter host IP: "
    read -r PARTNER_IP
    coproc NC_PROC { nc $PARTNER_IP $PORT; }
    exec 3<&"${NC_PROC[0]}"
    exec 4>&"${NC_PROC[1]}"
    CONNECTED=1
  else
    echo "Invalid choice. Please try again."
    setup_connection
  fi
}

function reset_connection() {
  if [[ -n "${NC_PROC_PID:-}" ]]; then
    exec 3<&-
    exec 4>&-
    wait "$NC_PROC_PID" 2>/dev/null
  fi

  if [[ $MODE == "host" ]]; then
    coproc NC_PROC { nc -l -p $PORT; }
    exec 3<&"${NC_PROC[0]}"
    exec 4>&"${NC_PROC[1]}"
  elif [[ $MODE == "client" ]]; then
    coproc NC_PROC { nc $PARTNER_IP $PORT; }
    exec 3<&"${NC_PROC[0]}"
    exec 4>&"${NC_PROC[1]}"
  fi
}

function send_msg() {
  if ((CONNECTED)); then
    echo "$1" >&4
  fi
}

function recv_msg() {
  if ((CONNECTED)); then
    if read -r -t 300 line <&3; then
      echo "$line"
    else
      echo ""
    fi
  else
    echo ""
  fi
}

function show_menu() {
  while read -t 0.1 -r dummy <&3; do :; done

  clear
  echo "========== GAME HUB =========="
  echo "1. Word Chain Game"
  echo "2. Math Duel Challenge"
  echo "3. Typing Speed Test"
  echo "4. Tic Tac Toe"
  echo "5. Number Guessing Game"
  echo "6. Hangman"
  echo "7. View Statistics"
  echo "8. Exit"

  if [[ $MODE == "host" ]]; then
    echo "Choose a game:"
    read -r choice
    send_msg "$choice"
  elif [[ $MODE == "client" ]]; then
    echo "Waiting for host to choose a game..."
    choice=$(recv_msg)
    echo "Host chose: $choice"
  fi

  case $choice in
  1) word_chain ;;
  2) math_duel ;;
  3) typing_speed_challenge ;;
  4) tic_tac_toe ;;
  5) number_guessing_game ;;
  6) hangman_game ;;
  7)
    show_stats
    show_menu
    ;;
  8) exit ;;
  *)
    echo "Invalid"
    sleep 1
    show_menu
    ;;
  esac
}

function is_valid_word() {
  local word="$1"
  if ! [[ "$word" =~ ^[a-zA-Z]+$ ]]; then
    return 1
  fi
  if [[ ${#word} -eq 1 && "$word" != "a" && "$word" != "i" ]]; then
    return 1
  fi
  if [[ -n "$DICT_FILE" ]]; then
    if ! grep -iq "^$word$" "$DICT_FILE"; then
      return 1
    fi
  fi
  return 0
}

function already_used() {
  local word="$1"
  for used in "${used_words[@]}"; do
    [[ "$used" == "$word" ]] && return 0
  done
  return 1
}

function word_chain() {
  echo -e "\n🔗 Starting Word Chain Game!"
  used_words=()
  last_letter=""

  if [[ $MODE == "host" ]]; then
    echo "Start the game with any valid English word:"
    read -r word
    word=$(echo "$word" | tr '[:upper:]' '[:lower:]')
    if ! is_valid_word "$word"; then
      echo "❌ Invalid word. You lose!"
      send_msg "WIN"
      update_stats "client_win"
      return
    fi
    used_words+=("$word")
    last_letter=${word: -1}
    send_msg "$word"
  else
    echo "Waiting for host to start..."
    word=$(recv_msg)
    if [[ "$word" == "WIN" ]]; then
      echo "🎉 You win! Host gave invalid word."
      update_stats "client_win"
      return
    fi
    echo "Host played: $word"
    used_words+=("$word")
    last_letter=${word: -1}
  fi
  while true; do
    if [[ $MODE == "host" ]]; then
      echo "Waiting for friend's word..."
      word=$(recv_msg)
      if [[ "$word" == "WIN" ]]; then
        echo "🎉 You win! Friend gave invalid word."
        update_stats "host_win"
        return
      fi
      echo "Friend played: $word"
      word=$(echo "$word" | tr '[:upper:]' '[:lower:]')
      if already_used "$word"; then
        echo "⚠  Friend repeated a word. You win!"
        send_msg "WIN"
        update_stats "host_win"
        return
      fi
      if [[ "${word:0:1}" != "$last_letter" ]]; then
        echo "⚠  Friend used wrong starting letter. You win!"
        send_msg "WIN"
        update_stats "host_win"
        return
      fi
      used_words+=("$word")
      last_letter=${word: -1}
      echo "Your turn! Enter a word starting with '$last_letter':"
      read -r word
      word=$(echo "$word" | tr '[:upper:]' '[:lower:]')
      if ! is_valid_word "$word"; then
        echo "❌ Invalid word. You lose!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      if already_used "$word"; then
        echo "❌ Word already used. You lose!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      if [[ "${word:0:1}" != "$last_letter" ]]; then
        echo "❌ Wrong starting letter. You lose!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      used_words+=("$word")
      last_letter=${word: -1}
      send_msg "$word"
    else
      echo "Your turn! Enter a word starting with '$last_letter':"
      read -r word
      word=$(echo "$word" | tr '[:upper:]' '[:lower:]')
      if ! is_valid_word "$word"; then
        echo "❌ Invalid word. You lose!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      if already_used "$word"; then
        echo "❌ Word already used. You lose!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      if [[ "${word:0:1}" != "$last_letter" ]]; then
        echo "❌ Wrong starting letter. You lose!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      used_words+=("$word")
      last_letter=${word: -1}
      send_msg "$word"
      echo "Waiting for friend's word..."
      word=$(recv_msg)
      if [[ "$word" == "WIN" ]]; then
        echo "🎉 You win! Friend gave invalid word."
        update_stats "client_win"
        return
      fi
      echo "Friend played: $word"
      word=$(echo "$word" | tr '[:upper:]' '[:lower:]')
      if already_used "$word"; then
        echo "⚠  Friend repeated a word. You win!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      if [[ "${word:0:1}" != "$last_letter" ]]; then
        echo "⚠  Friend used wrong starting letter. You win!"
        send_msg "WIN"
        update_stats "client_win"
        return
      fi
      used_words+=("$word")
      last_letter=${word: -1}
    fi
  done
}

function math_duel() {
  echo -e "\n🎯 Math Duel Challenge! Solve 5 problems quickly."
  
  if [[ $MODE == "host" ]]; then
    problems=()
    answers=()
    for ((i = 1; i <= 5; i++)); do
      num1=$((RANDOM % 20 + 1))
      num2=$((RANDOM % 20 + 1))
      op=$((RANDOM % 3))
      case $op in
      0)
        problems+=("$num1 + $num2")
        answers+=($((num1 + num2)))
        ;;
      1)
        problems+=("$num1 - $num2")
        answers+=($((num1 - num2)))
        ;;
      2)
        problems+=("$num1 * $num2")
        answers+=($((num1 * num2)))
        ;;
      esac
    done
    for p in "${problems[@]}"; do
      send_msg "$p"
    done
    for a in "${answers[@]}"; do
      send_msg "$a"
    done
  else
    problems=()
    for ((i = 1; i <= 5; i++)); do
      problems+=("$(recv_msg)")
    done
    answers=()
    for ((i = 1; i <= 5; i++)); do
      answers+=("$(recv_msg)")
    done
  fi

  score=0
  total_time=0
  my_scores=()
  my_times=()

  for ((i = 0; i < 5; i++)); do
    problem="${problems[$i]}"
    correct="${answers[$i]}"
    echo -n "Problem $((i + 1)): $problem = ? "
    start_time=$(date +%s)
    read -r answer
    end_time=$(date +%s)
    time_taken=$((end_time - start_time))
    total_time=$((total_time + time_taken))
    if [[ "$answer" == "$correct" ]]; then
      echo "✅ Correct! (${time_taken}s)"
      ((score++))
      my_scores+=("1")
    else
      echo "❌ Wrong! Correct answer was $correct"
      my_scores+=("0")
    fi
    my_times+=("$time_taken")
  done

  send_msg "${my_scores[*]}"
  send_msg "${my_times[*]}"

  other_scores=($(recv_msg))
  other_times=($(recv_msg))

  my_total_score=0
  my_total_time=0
  other_total_score=0
  other_total_time=0

  for ((i = 0; i < 5; i++)); do
    my_total_score=$((my_total_score + my_scores[i]))
    my_total_time=$((my_total_time + my_times[i]))
    other_total_score=$((other_total_score + other_scores[i]))
    other_total_time=$((other_total_time + other_times[i]))
  done

  echo -e "\nYour score: $my_total_score/5 in $my_total_time seconds."
  echo "Friend's score: $other_total_score/5 in $other_total_time seconds."

if ((my_total_score > other_total_score)); then
    echo "🏆 You win!"
    if [[ $MODE == "host" ]]; then
      update_stats "host_win"
    else
      update_stats "client_win"
    fi
elif ((my_total_score < other_total_score)); then
    echo "😔 You lose!"
    if [[ $MODE == "host" ]]; then
      update_stats "client_win"
    else
      update_stats "host_win"
    fi
else
    if ((my_total_score == 0)); then
        echo "🤝 Both players scored 0 - it's a draw!"
        update_stats "draw"
    elif ((my_total_time < other_total_time)); then
        echo "🏆 You win by speed!"
        if [[ $MODE == "host" ]]; then
          update_stats "host_win"
        else
          update_stats "client_win"
        fi
    elif ((my_total_time > other_total_time)); then
        echo "😔 You lose by speed!"
        if [[ $MODE == "host" ]]; then
          update_stats "client_win"
        else
          update_stats "host_win"
        fi
    else
        echo "🤝 It's a draw in both score and speed!"
        update_stats "draw"
    fi
fi
}

function typing_speed_challenge() {
  local prompts=(
    "The quick brown fox jumps over the lazy dog"
    "Pack my box with five dozen liquor jugs"
    "How vexingly quick daft zebras jump"
    "Bright vixens jump; dozy fowl quack"
    "Sphinx of black quartz judge my vow"
  )
  if [[ $MODE == "host" ]]; then
    prompt="${prompts[$RANDOM % ${#prompts[@]}]}"
    send_msg "$prompt"
  else
    prompt=$(recv_msg)
  fi

  clear
  echo -e "\n⌨ Typing Speed Challenge!"
  echo "Type the following sentence as fast as you can:"
  echo -e "\n\033[1m$prompt\033[0m\n"
  read -rp "Press Enter when ready to start..." dummy
  clear
  echo "Type this:"
  echo -e "\033[1m$prompt\033[0m\n"
  start_time=$(date +%s)
  read -rp "> " input
  end_time=$(date +%s)
  time_taken=$((end_time - start_time))
  prompt_length=${#prompt}
  word_count=$((prompt_length / 5))
  ((time_taken == 0)) && time_taken=1
  wpm=$((word_count * 60 / time_taken))

  IFS=' ' read -ra prompt_words <<<"$prompt"
  IFS=' ' read -ra input_words <<<"$input"

  correct_words=0
  incorrect_words=()

  for ((i = 0; i < ${#prompt_words[@]}; i++)); do
    if [[ "${prompt_words[i]}" == "${input_words[i]}" ]]; then
      ((correct_words++))
    else
      incorrect_words+=("${prompt_words[i]}")
    fi
  done

  accuracy=$((correct_words * 100 / ${#prompt_words[@]}))

  send_msg "$accuracy $time_taken $wpm ${incorrect_words[*]}"
  other=($(recv_msg))
  other_accuracy=${other[0]}
  other_time=${other[1]}
  other_wpm=${other[2]}
  other_incorrect=("${other[@]:3}")

  echo -e "\nYour results:"
  echo "Time: ${time_taken}s | Speed: ${wpm} WPM | Accuracy: ${accuracy}%"
  if ((accuracy < 100)); then
    echo "Mistakes in: ${incorrect_words[*]}"
  fi

  echo -e "\nFriend's results:"
  echo "Time: ${other_time}s | Speed: ${other_wpm} WPM | Accuracy: ${other_accuracy}%"
  if ((other_accuracy < 100)) && ((${#other_incorrect[@]} > 0)); then
    echo "Mistakes in: ${other_incorrect[*]}"
  fi

  if ((accuracy > other_accuracy)); then
    echo "🏆 You win!"
    if [[ $MODE == "host" ]]; then
      update_stats "host_win"
    else
      update_stats "client_win"
    fi
  elif ((accuracy < other_accuracy)); then
    if ((wpm > other_wpm)); then
      echo "😔 You lose due to accuracy, despite typing faster (${wpm} WPM vs ${other_wpm} WPM)!"
    else
      echo "😔 You lose!"
    fi
    if [[ $MODE == "host" ]]; then
      update_stats "client_win"
    else
      update_stats "host_win"
    fi
  else
    if ((time_taken < other_time)); then
      echo "🏆 You win by speed!"
      if [[ $MODE == "host" ]]; then
        update_stats "host_win"
      else
        update_stats "client_win"
      fi
    elif ((time_taken > other_time)); then
      echo "😔 You lose by speed!"
      if [[ $MODE == "host" ]]; then
        update_stats "client_win"
      else
        update_stats "host_win"
      fi
    else
      echo "🤝 It's a draw!"
      update_stats "draw"
    fi
  fi
}

function tic_tac_toe() {
  echo -e "\n🎮 Tic Tac Toe\n"
  board=(1 2 3 4 5 6 7 8 9)
  turn=0

  if [[ $MODE == "host" ]]; then
    ps="X"
    os="O"
    my_turn=true
  else
    ps="O"
    os="X"
    my_turn=false
  fi

  print_board() {
    clear
    printf "\n %s | %s | %s \n---+---+---\n %s | %s | %s \n---+---+---\n %s | %s | %s \n\n" "${board[@]}"
  }

  win() {
    local s=$1
    local lines=(
      0 1 2
      3 4 5
      6 7 8
      0 3 6
      1 4 7
      2 5 8
      0 4 8
      2 4 6
    )
    for ((i = 0; i < ${#lines[@]}; i += 3)); do
      if [[ ${board[${lines[i]}]} == "$s" && ${board[${lines[i + 1]}]} == "$s" && ${board[${lines[i + 2]}]} == "$s" ]]; then
        return 0
      fi
    done
    return 1
  }

  while ((turn < 9)); do
    print_board

    if $my_turn; then
      read -rp "Your move (1-9): " mv
      until [[ $mv =~ ^[1-9]$ ]] && [[ ${board[mv - 1]} != "$ps" ]] && [[ ${board[mv - 1]} != "$os" ]]; do
        echo "Invalid move or position taken. Try again."
        read -rp "Your move (1-9): " mv
      done
      board[mv - 1]="$ps"
      send_msg "$mv"

      print_board

      if win "$ps"; then
        echo "🏆 You win!"
        if [[ $MODE == "host" ]]; then
          update_stats "host_win"
        else
          update_stats "client_win"
        fi
        return
      fi
    else
      echo "Waiting for opponent's move..."
      mv=$(recv_msg)
      if [[ -z "$mv" ]]; then
        echo "Connection lost or no move received."
        return
      fi

      if [[ ! $mv =~ ^[1-9]$ ]] || [[ ${board[mv - 1]} == "$ps" ]] || [[ ${board[mv - 1]} == "$os" ]]; then
        echo "Received invalid move from opponent: $mv"
        return
      fi

      board[mv - 1]="$os"

      print_board

      if win "$os"; then
        echo "😢 You lose."
        if [[ $MODE == "host" ]]; then
          update_stats "client_win"
        else
          update_stats "host_win"
        fi
        return
      fi
    fi

    ((turn++))
    if $my_turn; then
      my_turn=false
    else
      my_turn=true
    fi
  done

  print_board
  echo "🤝 It's a draw."
  update_stats "draw"
}

function number_guessing_game() {
  echo -e "\n🎯 Number Guess Duel: Closest wins!\n"
  rounds=5
  score_me=0
  score_op=0

  for ((i = 1; i <= rounds; i++)); do
    echo -e "\n--- Round $i ---"

    if [[ $MODE == "host" ]]; then
      secret=$((RANDOM % 100 + 1))
      send_msg "$secret"
    else
      secret=$(recv_msg)
    fi

    echo "A number between 1 and 100 has been chosen!"
    read -rp "Your guess: " my_guess
    send_msg "$my_guess"

    op_guess=$(recv_msg)
    echo "Opponent guessed: $op_guess"
    echo "Secret number was: $secret"

    diff_me=$((my_guess > secret ? my_guess - secret : secret - my_guess))
    diff_op=$((op_guess > secret ? op_guess - secret : secret - op_guess))

    if ((diff_me < diff_op)); then
      echo "✅ You were closer!"
      ((score_me++))
    elif ((diff_op < diff_me)); then
      echo "❌ Opponent was closer!"
      ((score_op++))
    else
      echo "🤝 It's a tie! Both were equally close."
      ((score_me++))
      ((score_op++))
    fi
  done

  echo -e "\n📊 Final Score:"
  echo "You: $score_me"
  echo "Opponent: $score_op"

  if ((score_me > score_op)); then
    echo "🏆 You win the Number Guess Duel!"
    if [[ $MODE == "host" ]]; then
      update_stats "host_win"
    else
      update_stats "client_win"
    fi
  elif ((score_me < score_op)); then
    echo "😢 You lost the Number Guess Duel."
    if [[ $MODE == "host" ]]; then
      update_stats "client_win"
    else
      update_stats "host_win"
    fi
  else
    echo "🤝 It's a tie!"
    update_stats "draw"
  fi
}

function hangman_game() {
  echo -e "\n🎭 Starting Hangman Game!"

  while read -t 0.1 -r dummy <&3; do :; done

  if [[ -n "$DICT_FILE" ]]; then
    word=$(shuf -n 1 "$DICT_FILE" | tr '[:upper:]' '[:lower:]')
    while [[ ! $word =~ ^[a-z]{4,8}$ ]]; do
      word=$(shuf -n 1 "$DICT_FILE" | tr '[:upper:]' '[:lower:]')
    done
  else
    words=(apple banana orange grapefruit pineapple strawberry watermelon chocolate elephant)
    word=${words[$RANDOM % ${#words[@]}]}
  fi

  guessed=()
  wrong=()
  max_wrong=6
  game_over=0
  winner=0

  if [[ $MODE == "host" ]]; then
    send_msg "$word"
    echo "You are the host. Your opponent will guess the word."
    echo "The word is: $word"
    echo "Waiting for opponent to guess..."
    role="host"
    
  else
    echo "Waiting to receive word from host..."
    word=$(recv_msg)
    
    if [[ -z "$word" ]]; then
      echo "Failed to receive word. Returning to menu."
      return 1
    fi
    
    echo "You are the guesser. Try to find the word!"
    role="guesser"
  fi

  while ((game_over == 0)); do
    if [[ $role == "guesser" ]]; then
      clear
      echo -e "\nHangman Game"

      case ${#wrong[@]} in
        0) echo "  ____"; echo " |    |"; echo " |"; echo " |"; echo " |"; echo "_|_" ;;
        1) echo "  ____"; echo " |    |"; echo " |    O"; echo " |"; echo " |"; echo "_|_" ;;
        2) echo "  ____"; echo " |    |"; echo " |    O"; echo " |    |"; echo " |"; echo "_|_" ;;
        3) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|"; echo " |"; echo "_|_" ;;
        4) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|\\"; echo " |"; echo "_|_" ;;
        5) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|\\"; echo " |   /"; echo "_|_" ;;
        6) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|\\"; echo " |   / \\"; echo "_|_" ;;
      esac

      display=""
      for ((i = 0; i < ${#word}; i++)); do
        letter=${word:$i:1}
        if [[ " ${guessed[@]} " =~ " $letter " ]]; then
          display+="$letter "
        else
          display+="_ "
        fi
      done

      echo -e "\nWord: $display"
      echo "Wrong guesses: ${wrong[*]}"
      echo "Guesses left: $((max_wrong - ${#wrong[@]}))"

      valid=0
      while ((valid == 0)); do
        read -rp "Guess a letter: " guess
        guess=$(echo "$guess" | tr '[:upper:]' '[:lower:]')

        if [[ ${#guess} != 1 ]]; then
          echo "Please enter a single letter."
        elif [[ ! $guess =~ [a-z] ]]; then
          echo "Please enter a letter from A-Z."
        elif [[ " ${guessed[@]} " =~ " $guess " ]]; then
          echo "You already guessed that letter."
        else
          valid=1
        fi
      done

      guessed+=("$guess")

      if [[ "$word" == *"$guess"* ]]; then
        send_msg "correct $guess"
        won=1
        for ((i = 0; i < ${#word}; i++)); do
          letter=${word:$i:1}
          if [[ ! " ${guessed[@]} " =~ " $letter " ]]; then
            won=0
            break
          fi
        done
        if ((won)); then
          send_msg "win"
          game_over=1
          winner=1
        fi
      else
        send_msg "wrong $guess"
        wrong+=("$guess")
        if ((${#wrong[@]} >= max_wrong)); then
          send_msg "lose"
          game_over=1
          winner=0
        fi
      fi
    else
      echo "Waiting for guesser to make a move..."
      msg=$(recv_msg)
      
      if [[ -z "$msg" ]]; then
        echo "Connection lost! Ending game."
        game_over=1
        continue
      fi

      case $msg in
        correct*)
          guess=$(echo "$msg" | cut -d' ' -f2)
          guessed+=("$guess")
          echo "Guesser correctly guessed: $guess"
          won=1
          for ((i = 0; i < ${#word}; i++)); do
            letter=${word:$i:1}
            if [[ ! " ${guessed[@]} " =~ " $letter " ]]; then
              won=0
              break
            fi
          done
          if ((won)); then
            game_over=1
            winner=0
          fi
          ;;
        wrong*)
          guess=$(echo "$msg" | cut -d' ' -f2)
          wrong+=("$guess")
          echo "Guesser incorrectly guessed: $guess"
          if ((${#wrong[@]} >= max_wrong)); then
            game_over=1
            winner=1
          fi
          ;;
        win)
          game_over=1
          winner=0
          ;;
        lose)
          game_over=1
          winner=1
          ;;
      esac
    fi
  done

  clear
  echo -e "\nGame Over!"

  if [[ $role == "guesser" ]]; then
    if ((winner)); then
      echo "🎉 Congratulations! You guessed the word: $word"
      if [[ $MODE == "client" ]]; then
        update_stats "client_win"
      fi
    else
      echo "😢 You lost! The word was: $word"
      if [[ $MODE == "client" ]]; then
        update_stats "host_win"
      fi
    fi
  else
    if ((winner)); then
      echo "🏆 You win! The guesser failed to find the word: $word"
      if [[ $MODE == "host" ]]; then
        update_stats "host_win"
      fi
    else
      echo "😢 The guesser won! They found the word: $word"
      if [[ $MODE == "host" ]]; then
        update_stats "client_win"
      fi
    fi
  fi

  case ${#wrong[@]} in
    0) echo "  ____"; echo " |    |"; echo " |"; echo " |"; echo " |"; echo "_|_" ;;
    1) echo "  ____"; echo " |    |"; echo " |    O"; echo " |"; echo " |"; echo "_|_" ;;
    2) echo "  ____"; echo " |    |"; echo " |    O"; echo " |    |"; echo " |"; echo "_|_" ;;
    3) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|"; echo " |"; echo "_|_" ;;
    4) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|\\"; echo " |"; echo "_|_" ;;
    5) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|\\"; echo " |   /"; echo "_|_" ;;
    6) echo "  ____"; echo " |    |"; echo " |    O"; echo " |   /|\\"; echo " |   / \\"; echo "_|_" ;;
  esac

  while read -t 0.1 -r dummy <&3; do :; done
  sleep 0.5
}

init_stats
setup_connection
while true; do
  show_menu
  echo -e "\nGame over! Press enter to return to menu..."
  read -r dummy
done