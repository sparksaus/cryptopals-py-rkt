#lang racket

;; AES implementation in Racket...we'll see what happens
(require "tables.rkt")

(provide get-block
         aes-128-encrypt
         aes-128-decrypt
         aes-128-ecb-encrypt
         aes-128-ecb-decrypt
         aes-128-cbc-encrypt
         aes-128-cbc-decrypt)


;; number of columns for the state
(define Nb 4)
;; number of 32-bit words comprising the key
(define Nk 4)
;; length of the key in bytes
(define KeyLen 16)
;; number of rounds
(define Nr 10)
  

;;;; Cipher
;; byte state[4 Nb]
;; state = in
;; AddRoundKey(state  w[0  Nb-1])
;; for round = 1 step 1 to Nr-1
;;   SubBytes(state)
;;   ShiftRows(state)
;;   MixColumns(state)
;;   AddRoundKey(state  w[round*Nb]  (round+1)*Nb-1)
;; end for
;; SubBytes(state)
;; ShiftRows(state)
;; AddRoundKey(state  w[Nr*Nb  (Nr+1)*Nb-1])
;; out = state
(define (Cipher w in)
  (define state (box (AddRoundKey in (get-RoundKey w 0))))

  (for ([i (in-range 1 Nr)])
    (set-box! state
              (AddRoundKey (MixColumns
                            (ShiftRows
                             (SubBytes (unbox state))))
                           (get-RoundKey w i))))
     
  (AddRoundKey
   (ShiftRows
    (SubBytes (unbox state)))
   (get-RoundKey w Nr)))

;;;; InvCipher
;; AddRoundKey(state w[Nr*Nb, (Nr+1)*Nb - 1])
;; for round = Nr-1 step -1 downto 1
;;   InvShiftRows(state)
;;   InvSubBytes(state)
;;   AddRoundKey(state, w[round*Nb, (round+1)*Nb-1])
;;   InvMixColumns(state)
;; endfor
;; InvShiftRows(state)
;; InvSubBytes(state)
;; AddRoundKey(state, w[0, Nb-1])
(define (InvCipher w in)
  (define state (box (AddRoundKey in (get-RoundKey w Nr))))
  (for ([i (in-range (sub1 Nr) 0 -1)])
    #;(printf "Round: ~v\n" i)
    (set-box! state
              (InvMixColumns
               (AddRoundKey
                (InvSubBytes
                 (InvShiftRows (unbox state)))
                (get-RoundKey w i)))))
  (AddRoundKey
   (InvSubBytes
    (InvShiftRows (unbox state)))
   (get-RoundKey w 0)))

;; turns given ciphertxt into an input vector
(define (text->input-vector txt)
  (unless (= (bytes-length txt) 16)
    (error 'aes-128 "input is not of length 16: ~v" (string-length txt)))
  (for/vector ([i (in-range 4)])
    (for/vector ([j (in-range 4)])
      (bytes-ref txt (+ i (* j 4))))))

;; turns an input vector into a byte string
(define (input-vector->text vec)
  (apply bytes
         (flatten
          (for/list ([i (in-range 4)])
            (for/list ([j (in-range 4)])
              (state-at vec j i))))))

;; Creates the Round Key matrix for round i
(define (get-RoundKey w i)
  (for/vector ([j (in-range 4)])
    (for/vector ([k (in-range 4)])
      (bitwise-and
       #xFF
       (arithmetic-shift
        (vector-ref w (+ k (* i 4)))
        (- (* (add1 j) 8) 32))))))


;;;; AddRoundKey
;; A Round Key is added to the State by a simple
;; bitwise XOR operation. Each Round Key consists
;; of Nb words from the key schedule
(define (AddRoundKey state w)
  (define mat
    (for/vector ([i (in-range 4)])
      (for/vector ([j (in-range 4)])
        (bitwise-xor (state-at state i j)
                     (state-at w i j)))))
    #;(printf "End of AddRoundKey: \n")
    #;(print-matrix mat)
  mat)


;;;; ShiftRows
;; The bytes in the last three rows of the State are
;; cyclically shifted over different numbers of bytes
(define (ShiftRows state)
  (define mat
    (for/vector ([i (in-range 4)])
      (for/vector ([j (ring-list i)])
        (state-at state i j))))
    #;(printf "End of ShiftRows: \n")
    #;(print-matrix mat)
  mat)
;;;; InvShiftRows
(define (InvShiftRows state)
  (define mat
    (for/vector ([i (in-range 4)])
      (for/vector ([j (inv-ring-list i)])
        (state-at state i j))))
  #;(printf "End of InvShiftRows: \n")
  #;(print-matrix mat)
  mat)


;; Generates a list for iterating like a ring
(define (ring-list i)
  (match i
    [0 '(0 1 2 3)]
    [1 '(1 2 3 0)]
    [2 '(2 3 0 1)]
    [3 '(3 0 1 2)]))
(define (inv-ring-list i)
  (match i
    [0 '(0 1 2 3)]
    [1 '(3 0 1 2)]
    [2 '(2 3 0 1)]
    [3 '(1 2 3 0)]))

;; Useful debug to print matrix in hex
(define (print-matrix mat)
  (for ([i (in-range (vector-length mat))])
    (printf "~x ~x ~x ~x\n"
            (state-at mat i 0)
            (state-at mat i 1)
            (state-at mat i 2)
            (state-at mat i 3))))



;; flips the rows and columns of a vector of vectors
(define (flip-rows-columns vec)
  (for/vector ([i (in-range 4)])
    (for/vector ([j (in-range 4)])
      (state-at vec j i))))

;;;; MixColumns
;; Operates on the State column-by-column  treating each
;; column as a four-term polynomial. The columns are considered
;; as polynomials over GF(2^8) and multiplied modulo x^4+1 with a
;; fixed polynomial a(x).
(define (MixColumns state)
  (define mat
    (flip-rows-columns
     (for/vector ([i (in-range 4)])
       (for/vector ([j (in-range 4)])
         (mixer i j state)))))
  #;(printf "End of MixColumns:\n")
  #;(print-matrix mat)
  mat)
;; helper function for the MixColumns operation
(define (mixer i j state)
  (define lst (mix-idxes j))
  (bitwise-xor (XTIME (state-at state (first lst) i))
               (state-at state (second lst) i)
               (state-at state (third lst) i)
               (XTIME (state-at state (fourth lst) i))
               (state-at state (fifth lst) i)))
;; sort of a lame way of getting the proper values from  the state
(define (mix-idxes j)
  (match j
    [0 '(0 3 2 1 1)]
    [1 '(1 0 3 2 2)]
    [2 '(2 1 0 3 3)]
    [3 '(3 2 1 0 0)]))
;; also lame
(define (inv-mix-masks i)
  (match i
    [0 '(#x0e #x0b #x0d #x09)]
    [1 '(#x09 #x0e #x0b #x0d)]
    [2 '(#x0d #x09 #x0e #x0b)]
    [3 '(#x0b #x0d #x09 #x0e)]))

;;;; InvMixColumns
(define (InvMixColumns state)
  (define mat
    (flip-rows-columns
     (for/vector ([i (in-range 4)])
      (inv-mixer i state))))
  #;(printf "End of InvMixColumns:\n")
  #;(print-matrix mat)
  mat)

(define (inv-mixer i state)
  (for/vector ([k (in-range 4)])
    (define lst (inv-mix-masks k))
    (bitwise-xor (MULTIPLY (state-at state 0 i) (first lst))
                 (MULTIPLY (state-at state 1 i) (second lst))
                 (MULTIPLY (state-at state 2 i) (third lst))
                 (MULTIPLY (state-at state 3 i) (fourth lst)))))

;; XTIME macro
(define (XTIME num)
  (bitwise-and #xFF
               (bitwise-xor (arithmetic-shift num 1)
                            (if (= (arithmetic-shift num -7) 1)
                                #x01b
                                0))))
;; MULTIPLY macro
(define (MULTIPLY x y)
  #;(match y
    [#x09 (state-at galois-mult-table 0 x)]
    [#x0b (state-at galois-mult-table 1 x)]
    [#x0d (state-at galois-mult-table 2 x)]
    [#x0e (state-at galois-mult-table 3 x)])
  (bitwise-xor (* x (bitwise-and y 1))
               (* (XTIME x) (bitwise-and (arithmetic-shift y -1) 1))
               (* (XTIME (XTIME x)) (bitwise-and (arithmetic-shift y -2) 1))
               (* (XTIME (XTIME (XTIME x))) (bitwise-and (arithmetic-shift y -3) 1))
               (* (XTIME (XTIME (XTIME (XTIME x)))) (bitwise-and (arithmetic-shift y -4) 1))))

;; shorthand for getting values from state
(define (state-at state i j)
  (vector-ref (vector-ref state i) j))

;;;; SubBytes
;; SubBytes() is a non-linear byte substitution that
;; operates independently on each byte of the State
;; using a substitution table (S-box). 
(define (SubBytes state)
  (define mat
    (for/vector ([i (in-range 4)])
      (for/vector ([j (in-range 4)])
        (vector-ref Sbox
                    (state-at state i j)))))
  #;(printf "End of SubBytes:\n")
  #;(print-matrix mat)
  mat)
;;;; InvSubBytes
(define (InvSubBytes state)
  (define mat
    (for/vector ([i (in-range 4)])
      (for/vector ([j (in-range 4)])
        (vector-ref invSbox
                    (state-at state i j)))))
  #;(printf "End of InvSubBytes:\n")
  #;(print-matrix mat)
  mat)


;;;; Word
;; takes in 4 byte values an combines them
;; into one 32-bit value
(define (Word blist)
  (let ([result (box 0)])
    (for ([i (in-range 4)])
      (set-box! result (bitwise-ior (unbox result)
                                    (arithmetic-shift (list-ref blist i)
                                                      (- 32 (* 8 (add1 i)))))))
    (unbox result)))




;;;; Key Expansion
;;; byte key[4*Nk]  word w[Nb*(Nr+1)]  Nk
;; word temp
;; i = 0
;; while i < Nk
;;   w[i] = word(key[4*i]  key[4*i+1]  key[4*i+2]  key[4*i+3])
;;   i += 1
;; end while
;; i = Nk
;; while (i < Nb * (Nr+1))
;;   temp = w[i-1]
;;   if (i mod Nk == 0)
;;     temp = SubWord(RotWord(temp)) XOR Rcon[i/Nk]
;;   else if (Nk > 6 and i mod Nk = 4)
;;     temp = SubWord(temp)
;;   end if
;;   w[i] = w[i-Nk] XOR temp
;;   i += 1
;; endwhile

;; expands according to pseudocode above
(define (key-expansion key)
  (let ([w (box (vector))])
    ;; first while loop
    (for ([i (in-range 0 Nk)])
      ; (printf "~v: ~x\n" i )
      (set-box! w
                (vector-append (unbox w)
                               (vector (key-pieces key i)))))
    ;; second while loop
    (for ([i (in-range Nk (* Nb (add1 Nr)))])
   
      (define t (let ([temp (vector-ref (unbox w) (sub1 (vector-length (unbox w))))])
                  (cond
                    [(= (modulo i Nk) 0)
                     (bitwise-xor (SubWord (RotWord temp))
                                  (vector-ref Rcon (sub1 (/ i Nk))))]
                    [(and (> Nk 6)
                          (= (modulo i Nk) 4))
                     (SubWord temp)]
                    [else temp])))
      #;(printf "~v: ~x\n" i (bitwise-xor t
                                          (vector-ref (unbox w) (- i Nk))))
      (set-box! w
                (vector-append (unbox w) (vector (bitwise-xor t
                                                              (vector-ref (unbox w) (- i Nk)))))))
    (unbox w)))

;; get key[4*i] ... key[4*i+3]
;(: key-pieces (-> Bytes Real Integer))
(define (key-pieces key i)
  (integer-bytes->integer (list->bytes
                           (reverse
                            (bytes->list
                             (get-4bytes key i))))
                          #f))


;;;; Subword
;; Takes a four-byte input word and applies
;; the S-box to each of the four bytes to produce
;; an output word
(define (SubWord num)
  (Word (map get-sbox-value
             (map (λ (e) (get-byte num e))
                  (list 0 1 2 3)))))

;; Extract 4bytes from a [num-bits]-bit key
(define (get-4bytes num i)
  (subbytes num (* i 4) (* (add1 i) 4)))

;; Extract a byte from a 32-bit integer
(define (get-byte num i)
  (bitwise-and #xFF
               (arithmetic-shift num
                                 (- (- 32 (* 8 (add1 i)))))))

;; xor two byte strings together because that's the way it should be
(define (xor-bstrs bstr1 bstr2)
  (unless (equal? (bytes-length bstr1)
                  (bytes-length bstr2))
    (error 'xor-bstrs "unequal length: ~v ~v\n"
           (bytes-length bstr1)
           (bytes-length bstr2)))
  (list->bytes (map (λ (l) (apply bitwise-xor l))
                    (zip (bytes->list bstr1)
                         (bytes->list bstr2)))))

;; like the python zip function
(define (zip lst1 lst2)
  (map list lst1 lst2))


;; Gets the value sbox[i]
(define (get-sbox-value i)
  (vector-ref Sbox i))

;;;; RotWord
(define (RotWord num)
  (define blist
    (map (λ (e) (get-byte num e))
         (list 0 1 2 3)))
  (Word (list (second blist)
              (third blist)
              (fourth blist)
              (first blist))))

;; gets a block from a byte string
(define (get-block txt i [blocksize 16])
  (subbytes txt (* blocksize i) (* blocksize (add1 i))))

;; Actual encryption of a single block
;; Takes in two byte strings as the plaintext and key
(define (aes-128-encrypt txt key)
  (unless (= 16 (bytes-length txt))
    (error 'encrypt "input is not 16 bytes ~v\n" (bytes-length txt)))
  (unless (= 16 (bytes-length key))
    (error 'encrypt "key is not 16 bytes ~v\n" (bytes-length key)))
  (input-vector->text
   (Cipher (key-expansion key)
           (text->input-vector txt))))

;; Decryption of a single block
;; Takes in two byte strings as the ciphertext and key
(define (aes-128-decrypt txt key)
  (unless (= 16 (bytes-length txt))
    (error 'decrypt "input is not 16 bytes ~v\n" (bytes-length txt)))
  (unless (= 16 (bytes-length key))
    (error 'decrypt "key is not 16 bytes ~v\n" (bytes-length key)))
  (input-vector->text
   (InvCipher (key-expansion key)
              (text->input-vector txt))))

;; ECB mode for AES
(define (aes-128-ecb-encrypt txt key)
  (unless (= 16 (bytes-length key))
    (error 'encrypt "key is not 16 bytes ~v\n" (bytes-length key)))
  (unless (= 0 (modulo (bytes-length txt) 16))
    (error 'encrypt "input is not multiple of 16 bytes: ~v\n"
           (bytes-length txt)))
  (apply bytes-append
          (for/list ([i (in-range (/ (bytes-length txt) 16))])
            (aes-128-encrypt (get-block txt i)
                             key))))
(define (aes-128-ecb-decrypt txt key)
  (unless (= 16 (bytes-length key))
    (error 'encrypt "key is not 16 bytes ~v\n" (bytes-length key)))
  (unless (= 0 (modulo (bytes-length txt) 16))
    (error 'encrypt "input is not multiple of 16 bytes: ~v\n"
           (bytes-length txt)))
  (apply bytes-append
          (for/list ([i (in-range (/ (bytes-length txt) 16))])
            (aes-128-decrypt (get-block txt i)
                             key))))
;; CBC mode for AES
(define (aes-128-cbc-encrypt txt key iv)
  ;; check lengths of everything
  (unless (= 16 (bytes-length key))
    (error 'encrypt "key is not 16 bytes ~v\n" (bytes-length key)))
  (unless (= 16 (bytes-length iv))
    (error 'encrypt "iv is not 16 bytes ~v\n" (bytes-length iv)))
  (unless (= 0 (modulo (bytes-length txt) 16))
    (error 'encrypt "input is not multiple of 16 bytes: ~v\n"
           (bytes-length txt)))
  
  (define last-block (box iv))
  (apply bytes-append
         (for/list ([i (in-range (/ (bytes-length txt) 16))])
           (define cur-block (get-block txt i))
           (define enc
             (aes-128-encrypt (xor-bstrs cur-block (unbox last-block))
                              key))
           (set-box! last-block enc)
           enc)))
(define (aes-128-cbc-decrypt txt key iv)
  (unless (= 16 (bytes-length key))
    (error 'encrypt "key is not 16 bytes ~v\n" (bytes-length key)))
  (unless (= 16 (bytes-length iv))
    (error 'encrypt "iv is not 16 bytes ~v\n" (bytes-length iv)))
  (unless (= 0 (modulo (bytes-length txt) 16))
    (error 'encrypt "input is not multiple of 16 bytes: ~v\n"
           (bytes-length txt)))
  (define last-block (box iv))
  (apply bytes-append
         (for/list ([i (in-range (/ (bytes-length txt) 16))])
           (define cur-block (get-block txt i))
           (define dec (aes-128-decrypt cur-block key))
           (define pt (xor-bstrs dec (unbox last-block)))
           (set-box! last-block cur-block)
           pt)))


(module+ test
  (require rackunit)
  (check-equal? (get-byte 65 3)
                65)
  ;; #x65666768
  (check-equal? (get-byte 1701209960 0)
                #x65)
  (check-equal? (get-byte 1701209960 1)
                #x66)
  (check-equal? (get-byte 1701209960 2)
                #x67)
  (check-equal? (get-byte 1701209960 3)
                #x68)
  ;; #x01020304
  (check-equal? (Word (list 1 2 3 4))
                #x01020304)
  (check-equal? (SubWord #x01020304)
                #x7c777bf2)
  (check-equal? (RotWord #x01020304)
                #x02030401)
  (check-equal? (XTIME #x57)
                #xae)
  (check-equal? (XTIME #xae)
                #x47)
  (check-equal? (arithmetic-shift #x47 1)
                #x8e)
  (check-equal? (XTIME #x47)
                #x8e)
  (check-equal? (XTIME #x8e)
                #x07)
  (define bkey #"\x2b\x7e\x15\x16\x28\xae\xd2\xa6\xab\xf7\x15\x88\x09\xcf\x4f\x3c")
  (define binput #"\x32\x43\xf6\xa8\x88\x5a\x30\x8d\x31\x31\x98\xa2\xe0\x37\x07\x34")
  (define binputv (vector (vector #x32 #x88 #x31 #xe0)
                          (vector #x43 #x5a #x31 #x37)
                          (vector #xf6 #x30 #x98 #x07)
                          (vector #xa8 #x8d #xa2 #x34)))
  (check-equal? (text->input-vector binput)
                binputv)
  (define bw (vector-immutable #x2b7e1516 #x28aed2a6 #xabf71588 #x09cf4f3c #xa0fafe17
                               #x88542cb1 #x23a33939 #x2a6c7605 #xf2c295f2 #x7a96b943
                               #x5935807a #x7359f67f #x3d80477d #x4716fe3e #x1e237e44
                               #x6d7a883b #xef44a541 #xa8525b7f #xb671253b #xdb0bad00
                               #xd4d1c6f8 #x7c839d87 #xcaf2b8bc #x11f915bc #x6d88a37a
                               #x110b3efd #xdbf98641 #xca0093fd #x4e54f70e #x5f5fc9f3
                               #x84a64fb2 #x4ea6dc4f #xead27321 #xb58dbad2 #x312bf560
                               #x7f8d292f #xac7766f3 #x19fadc21 #x28d12941 #x575c006e
                               #xd014f9a8 #xc9ee2589 #xe13f0cc8 #xb6630ca6))
  (check-equal? (get-RoundKey bw 0)
                (vector (vector #x2b #x28 #xab #x09)
                        (vector #x7e #xae #xf7 #xcf)
                        (vector #x15 #xd2 #x15 #x4f)
                        (vector #x16 #xa6 #x88 #x3c)))
  (check-equal? (key-expansion bkey)
                bw)
  (check-equal? (input-vector->text binputv)
                binput)
  (check-equal? (InvSubBytes (SubBytes binputv))
                binputv)
  (check-equal? (InvShiftRows (ShiftRows binputv))
                binputv)
  (check-equal? (InvMixColumns (MixColumns binputv))
                binputv)
  (check-equal? (Cipher (key-expansion bkey)
                        binputv)
                (vector (vector #x39 #x02 #xdc #x19)
                        (vector #x25 #xdc #x11 #x6a)
                        (vector #x84 #x09 #x85 #x0b)
                        (vector #x1d #xfb #x97 #x32)))
  (check-equal? (InvCipher (key-expansion bkey)
                           (vector (vector #x39 #x02 #xdc #x19)
                        (vector #x25 #xdc #x11 #x6a)
                        (vector #x84 #x09 #x85 #x0b)
                        (vector #x1d #xfb #x97 #x32)))
                binputv)
  (check-equal? (aes-128-encrypt binput bkey)
                #"\x39\x25\x84\x1d\x02\xdc\x09\xfb\xdc\x11\x85\x97\x19\x6a\x0b\x32")
  ;; Test vector 1
  (define test1input #"\x00\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\xcc\xdd\xee\xff")
  (define test1key #"\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f")
  (define test1output #"\x69\xc4\xe0\xd8\x6a\x7b\x04\x30\xd8\xcd\xb7\x80\x70\xb4\xc5\x5a")
  (check-equal? (aes-128-encrypt test1input test1key)
                test1output)
  (check-equal? (aes-128-decrypt test1output test1key)
                test1input)
  (check-equal? (aes-128-decrypt (aes-128-encrypt test1input test1key)
                                 test1key)
                test1input)
  (check-equal? (aes-128-ecb-encrypt (bytes-append test1input test1input)
                                     test1key)
                (bytes-append test1output test1output))
  (check-equal? (aes-128-ecb-decrypt
                 (aes-128-ecb-encrypt (bytes-append test1input test1input) test1key)
                 test1key)
                (bytes-append test1input test1input))
  )
